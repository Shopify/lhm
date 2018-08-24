# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'test_helper'
require 'yaml'
require 'active_support'

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

  def connect_master!
    connect!(
      '127.0.0.1',
      $db_config['master']['port'],
      $db_config['master']['user'],
      $db_config['master']['password'],
      $db_config['master']['socket']
    )
  end

  def connect_slave!
    connect!(
      '127.0.0.1',
      $db_config['slave']['port'],
      $db_config['slave']['user'],
      $db_config['slave']['password'],
      $db_config['slave']['socket']
    )
  end

  def connect!(hostname, port, user, password, socket)
    adapter = ar_conn(hostname, port, user, password, socket)
    Lhm.setup(adapter)
    unless defined?(@@cleaned_up)
      Lhm.cleanup(true)
      @@cleaned_up  = true
    end
    @connection = adapter
  end

  def ar_conn(host, port, user, password, socket)
    ActiveRecord::Base.establish_connection(
      :adapter  => 'mysql2',
      :host     => host,
      :username => user,
      :port     => port,
      :password => password,
      :socket   => socket,
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

  def slave(&block)
    if master_slave_mode?
      connect_slave!

      # need to wait for the slave to catch up. a better method would be to
      # check the master binlog position and wait for the slave to catch up
      # to that position.
      sleep 1
    else
      connect_master!
    end

    yield block

    if master_slave_mode?
      connect_master!
    end
  end

  # Helps testing behaviour when another client locks the db
  def start_locking_thread(lock_for, queue, locking_query)
    Thread.new do
      conn = Mysql2::Client.new(host: '127.0.0.1', database: $db_name, user: 'root', port: 3306)
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

  def hash_slice(hash, keys)
    return hash.slice(*keys) if hash.respond_to?(:slice)
    keys.each { |k| [k, hash[k]] }.to_h
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

  def master_slave_mode?
    !!ENV['MASTER_SLAVE']
  end

  #
  # Misc
  #

  def capture_stdout
    out = StringIO.new
    $stdout = out
    yield
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
