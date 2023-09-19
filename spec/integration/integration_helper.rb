# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'test_helper'
require 'yaml'
require 'active_support'
require 'logger'

begin
  $db_config = YAML.load_file(File.expand_path(File.dirname(__FILE__)) + '/database.yml')
rescue StandardError => e
  puts "Run install.sh to setup database"
  raise e
end

$db_name = 'test'

require 'lhm/table'
require 'lhm/sql_helper'

module IntegrationHelper

  def self.included(base)
    base.after(:each) do
      cleanup_connection = new_mysql_connection
      results = cleanup_connection.query("SELECT table_name FROM information_schema.tables WHERE table_schema = '#{$db_name}';")
      table_names_for_cleanup = results.map { |row| "#{$db_name}." + row.values.first }
      cleanup_connection.query("DROP TABLE IF EXISTS #{table_names_for_cleanup.join(', ')};") if table_names_for_cleanup.length > 0
    end
  end

  #
  # Connectivity
  #
  def connection
    @connection
  end

  def mysql_version
    @mysql_version ||= begin
      # This SQL returns a value of shape: X.Y.ZZ-AA-log
      result = connection.query("SELECT VERSION()")
      result.dig(0, 0).split("-", 2)[0]
    end
  end

  def connect_proxysql!
    connect!(
      '127.0.0.1',
      $db_config['proxysql']['port'],
      $db_config['proxysql']['user'],
      $db_config['proxysql']['password'],
    )
  end

  def connect_master!
    connect!(
      '127.0.0.1',
      $db_config['master']['port'],
      $db_config['master']['user'],
      $db_config['master']['password'],
    )
  end

  def connect_replica!
    connect!(
      '127.0.0.1',
      $db_config['replica']['port'],
      $db_config['replica']['user'],
      $db_config['replica']['password'],
    )
  end

  def connect_master_with_toxiproxy!
    connect!(
      '127.0.0.1',
      $db_config['master_toxic']['port'],
      $db_config['master_toxic']['user'],
      $db_config['master_toxic']['password'])
  end

  def connect!(hostname, port, user, password)
    Lhm.setup(ar_conn(hostname, port, user, password))
    unless defined?(@@cleaned_up)
      Lhm.cleanup(true)
      @@cleaned_up  = true
    end
    @connection = Lhm.connection
  end

  def ar_conn(host, port, user, password)
    ActiveRecord::Base.establish_connection(
      :adapter  => 'mysql2',
      :host     => host,
      :username => user,
      :port     => port,
      :password => password,
      :database => $db_name
    )
    ActiveRecord::Base.connection
  end

  def select_one(*args)
    @connection.select_one(*args)
  end

  def select_value(*args)
    @connection.select_value(*args)
  end

  def execute(*args)
    retries = 10
    begin
      @connection.execute(*args)
    rescue => e
      if (retries -= 1) > 0 && e.message =~ /Table '.*?' doesn't exist/
        sleep 0.1
        retry
      else
        raise
      end
    end
  end

  def replica(&block)
    if master_replica_mode?
      connect_replica!

      # need to wait for the replica to catch up. a better method would be to
      # check the master binlog position and wait for the replica to catch up
      # to that position.
      sleep 1
    else
      connect_master!
    end

    yield block

    if master_replica_mode?
      connect_master!
    end
  end

  # Helps testing behaviour when another client locks the db
  def start_locking_thread(lock_for, queue, locking_query)
    Thread.new do
      conn = new_mysql_connection
      conn.query('BEGIN')
      conn.query(locking_query)
      queue.push(true)
      sleep(lock_for) # Sleep for log so LHM gives up
      conn.query('ROLLBACK')
    end
  end

  #
  # Test Data
  #

  def fixture(name)
    File.read($fixtures.join("#{ name }.ddl"))
  end

  def table_create(fixture_name)
    execute "drop table if exists `#{ fixture_name }`"
    execute fixture(fixture_name)
    table_read(fixture_name)
  end

  def table_rename(from_name, to_name)
    execute "rename table `#{ from_name }` to `#{ to_name }`"
  end

  def table_read(fixture_name)
    Lhm::Table.parse(fixture_name, @connection)
  end

  def data_source_exists?(table)
    connection.data_source_exists?(table.name)
  end

  def new_mysql_connection(role='master')
    Mysql2::Client.new(
      host: '127.0.0.1',
      database: $db_name,
      username: $db_config[role]['user'],
      password: $db_config[role]['password'],
      port: $db_config[role]['port'],
      socket: $db_config[role]['socket']
    )
  end

  #
  # Database Helpers
  #

  def count(table, column, value)
    query = "select count(*) from #{ table } where #{ column } = '#{ value }'"
    select_value(query).to_i
  end

  def count_all(table)
    query = "select count(*) from `#{ table }`"
    select_value(query).to_i
  end

  def index_on_columns?(table_name, cols, type = :non_unique)
    key_name = Lhm::SqlHelper.idx_name(table_name, cols)

    index?(table_name, key_name, type)
  end

  def index?(table_name, key_name, type = :non_unique)
    non_unique = type == :non_unique ? 1 : 0

    !!select_one(%Q<
      show indexes in `#{ table_name }`
     where key_name = '#{ key_name }'
       and non_unique = #{ non_unique }
    >)
  end

  #
  # Environment
  #

  def master_replica_mode?
    !!ENV['MASTER_REPLICA']
  end

  #
  # Misc
  #

  def capture_stdout
    out = StringIO.new
    $stdout = out
    logger = Logger.new($stdout)
    yield logger
    return out.string
  ensure
    $stdout = ::STDOUT
  end

  def simulate_failed_migration
    Lhm::Entangler.class_eval do
      alias_method :old_after, :after
      def after
        true
      end
    end

    yield
  ensure
    Lhm::Entangler.class_eval do
      undef_method :after
      alias_method :after, :old_after
      undef_method :old_after
    end
  end
end
