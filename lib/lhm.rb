# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/table_name'
require 'lhm/table'
require 'lhm/invoker'
require 'lhm/throttler'
require 'lhm/version'
require 'lhm/cleanup/current'
require 'lhm/sql_retry'
require 'lhm/proxysql_helper'
require 'lhm/connection'
require 'lhm/test_support'
require 'lhm/railtie' if defined?(Rails::Railtie)
require 'logger'

# Large hadron migrator - online schema change tool
#
# @example
#
#   Lhm.change_table(:users) do |m|
#     m.add_column(:arbitrary, "INT(12)")
#     m.add_index([:arbitrary, :created_at])
#     m.ddl("alter table %s add column flag tinyint(1)" % m.name)
#   end
#
module Lhm
  extend Throttler
  extend self

  DEFAULT_LOGGER_OPTIONS = { level: Logger::INFO, file: STDOUT }

  # Alters a table with the changes described in the block
  #
  # @param [String, Symbol] table_name Name of the table
  # @param [Hash] options Optional options to alter the chunk / switch behavior
  # @option options [Integer] :stride
  #   Size of a chunk (defaults to: 2,000)
  # @option options [Integer] :throttle
  #   Time to wait between chunks in milliseconds (defaults to: 100)
  # @option options [Integer] :start
  #   Primary Key position at which to start copying chunks
  # @option options [Integer] :limit
  #   Primary Key position at which to stop copying chunks
  # @option options [Boolean] :atomic_switch
  #   Use atomic switch to rename tables (defaults to: true)
  #   If using a version of mysql affected by atomic switch bug, LHM forces user
  #   to set this option (see SqlHelper#supports_atomic_switch?)
  # @option options [Boolean] :reconnect_with_consistent_host
  #   Active / Deactivate ProxySQL-aware reconnection procedure (default to: false)
  # @yield [Migrator] Yielded Migrator object records the changes
  # @return [Boolean] Returns true if the migration finishes
  # @raise [Error] Raises Lhm::Error in case of a error and aborts the migration
  def change_table(table_name, options = {}, &block)
    with_flags(options) do
      origin = Table.parse(table_name, connection)
      invoker = Invoker.new(origin, connection, options)
      block.call(invoker.migrator)
      invoker.run
      true
    end
  end

  # Cleanup tables and triggers
  #
  # @param [Boolean] run execute now or just display information
  # @param [Hash] options Optional options to alter cleanup behaviour
  # @option options [Time] :until
  #   Filter to only remove tables up to specified time (defaults to: nil)
  def cleanup(run = false, options = {})
    lhm_tables = connection.select_values('show tables').select { |name| name =~ /^lhm(a|n)_/ }
    if options[:until]
      lhm_tables.select! do |table|
        table_date_time = Time.strptime(table, 'lhma_%Y_%m_%d_%H_%M_%S')
        table_date_time <= options[:until]
      end
    end

    lhm_triggers = connection.select_values('show triggers').collect do |trigger|
      trigger.respond_to?(:trigger) ? trigger.trigger : trigger
    end.select { |name| name =~ /^lhmt/ }

    drop_tables_and_triggers(run, lhm_triggers, lhm_tables)
  end

  def cleanup_current_run(run, table_name, options = {})
    Lhm::Cleanup::Current.new(run, table_name, connection, options).execute
  end

  # Setups DB connection
  #
  # @param [ActiveRecord::Base] connection ActiveRecord Connection
  def setup(connection)
    @@connection = Connection.new(connection: connection)
  end

  # Returns DB connection (or initializes it if not created yet)
  def connection
    @@connection ||= begin
                       raise 'Please call Lhm.setup' unless defined?(ActiveRecord)
                       @@connection = Connection.new(connection: ActiveRecord::Base.connection)
                     end
  end

  def self.logger=(new_logger)
    @@logger = new_logger
  end

  def self.logger
    @@logger ||=
      begin
        logger = Logger.new(DEFAULT_LOGGER_OPTIONS[:file])
        logger.level = DEFAULT_LOGGER_OPTIONS[:level]
        logger.formatter = nil
        logger
      end
  end

  @@disallow_inline = false

  # Use to control the inline-execution of Lhm migrations - by default migrations are inlined
  # in test and development environments, and in some cases that's not desireable.
  def self.disallow_inline!
    @@disallow_inline = true
  end

  def self.inline_allowed?
    !@@disallow_inline
  end

  private

  def drop_tables_and_triggers(run = false, triggers, tables)
    if run
      triggers.each do |trigger|
        connection.execute("drop trigger if exists #{trigger}")
      end
      logger.info("Dropped triggers #{triggers.join(', ')}")

      tables.each do |table|
        connection.execute("drop table if exists #{table}")
      end
      logger.info("Dropped tables #{tables.join(', ')}")

      true
    elsif tables.empty? && triggers.empty?
      logger.info('Everything is clean. Nothing to do.')
      true
    else
      logger.info("Would drop LHM backup tables: #{tables.join(', ')}.")
      logger.info("Would drop LHM triggers: #{triggers.join(', ')}.")
      logger.info('Run with Lhm.cleanup(true) to drop all LHM triggers and tables, or Lhm.cleanup_current_run(true, table_name) to clean up a specific LHM.')
      false
    end
  end

  def with_flags(options)
    old_flags = {
      reconnect_with_consistent_host: Lhm.connection.reconnect_with_consistent_host,
    }

    Lhm.connection.reconnect_with_consistent_host = options[:reconnect_with_consistent_host] || false

    yield
  ensure
    Lhm.connection.reconnect_with_consistent_host = old_flags[:reconnect_with_consistent_host]
  end
end
