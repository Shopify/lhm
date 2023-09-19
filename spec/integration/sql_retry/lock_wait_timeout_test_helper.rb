require 'integration/integration_helper'

class LockWaitTimeoutTestHelper

  def initialize(lock_duration:, innodb_lock_wait_timeout:)
    # This connection will be used exclusively to setup the test,
    # assert pre-conditions and assert post-conditions.
    # We choose to use a `Mysql2::Client` connection instead of
    # `ActiveRecord::Base.establish_connection` because of AR's connection
    # pool which forces thread syncronization. In this test,
    # we want to intentionally create a lock to test retries,
    # so that is an anti-feature.
    @main_conn = new_mysql_connection

    @lock_duration = lock_duration

    raise ArgumentError, "innodb_lock_wait_timeout must be an integer" if innodb_lock_wait_timeout.class != Integer

    result = @main_conn.query("SELECT VERSION()")
    mysql_version = result.to_a.dig(0, "VERSION()").split("-", 2)[0]

    if mysql_version.start_with?("8")
      @innodb_lock_wait_timeout = innodb_lock_wait_timeout
    else
      # While implementing this, I discovered that MySQL seems to have an off-by-one
      # bug with the innodb_lock_wait_timeout. If you ask it to wait 2 seconds, it will wait 3.
      # In order to avoid surprisingly the user, let's account for that here, but also
      # guard against a case where we go below 1, the minimum value.
      raise ArgumentError, "innodb_lock_wait_timeout must be greater than or equal to 2" unless innodb_lock_wait_timeout >= 2
      @innodb_lock_wait_timeout = innodb_lock_wait_timeout - 1
    end

    @threads = []
    @queue = Queue.new
  end

  def create_table_to_lock(connection = main_conn)
    connection.query("DROP TABLE IF EXISTS #{test_table_name};")
    connection.query("CREATE TABLE #{test_table_name} (id INT, PRIMARY KEY (id)) ENGINE=InnoDB;")
  end

  def hold_lock(seconds = lock_duration, queue = @queue)
    # We are intentionally choosing to create a gap in the between the IDs to
    # create a gap lock.
    insert_records_at_ids(main_conn, [1001,1003])
    locked_id = 1002

    # This is the locking thread. It creates gap lock. It must be created first.
    @threads << Thread.new do
      conn = new_mysql_connection
      conn.query("START TRANSACTION;")
      conn.query("DELETE FROM #{test_table_name} WHERE id=#{locked_id}") # we now have the lock
      queue.push(true) # this will signal the waiting thread to unblock, now that the lock is held
      sleep seconds # hold the lock, while the waiting thread is waiting/retrying
      conn.query("ROLLBACK;") # release the lock
    end

    return locked_id
  end

  def record_count(connection = main_conn)
    response = connection.query("SELECT COUNT(id) FROM #{test_table_name}")
    response.first.values.first
  end

  def with_waiting_lock(lock_time = @lock_duration, queue = @queue)
    @threads << Thread.new do
      conn = new_mysql_connection
      conn.query("SET SESSION innodb_lock_wait_timeout = #{innodb_lock_wait_timeout}") # set timeout to be less than lock_time, so the timeout will happen
      queue.pop # this will block until the lock thread establishes lock
      yield(conn) # invoke the code that should retry while lock is held
    end
  end

  def trigger_wait_lock
    @threads.each(&:join)
  end

  def insert_records_at_ids(connection, ids)
    ids.each do |id|
      mysql_exec(connection, "INSERT INTO #{test_table_name} (id) VALUES (#{id})")
    end
  end

  private

  attr_reader :main_conn, :lock_duration, :innodb_lock_wait_timeout

  def new_mysql_connection
    Mysql2::Client.new(
      host: '127.0.0.1',
      username: db_config['master']['user'],
      password: db_config['master']['password'],
      port: db_config['master']['port'],
      database: test_db_name
    )
  end

  def test_db_name
    @test_db_name ||= "test"
  end

  def db_config
    @db_config ||= YAML.load_file(File.expand_path(File.dirname(__FILE__)) + '/../database.yml')
  end

  def test_table_name
    @test_table_name ||= "lock_wait"
  end

  private

  def mysql_exec(connection, statement)
    if connection.class == Mysql2::Client
      connection.query(statement)
    elsif connection.class.to_s.include?("ActiveRecord")
      connection.execute(statement)
    else
      raise StandardError.new("Unrecognized MySQL client")
    end
  end
end
