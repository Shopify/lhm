# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/chunker'
require 'lhm/entangler'
require 'lhm/atomic_switcher'
require 'lhm/locked_switcher'
require 'lhm/migrator'

module Lhm
  # Copies an origin table to an altered destination table. Live activity is
  # synchronized into the destination table using triggers.
  #
  # Once the origin and destination tables have converged, origin is archived
  # and replaced by destination.
  class Invoker
    include SqlHelper
    LOCK_WAIT_TIMEOUT_DELTA = 10
    INNODB_LOCK_WAIT_TIMEOUT_MAX = 1073741824.freeze # https://dev.mysql.com/doc/refman/5.7/en/innodb-parameters.html#sysvar_innodb_lock_wait_timeout
    LOCK_WAIT_TIMEOUT_MAX = 31536000.freeze # https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html

    attr_reader :migrator, :connection

    def initialize(origin, connection, options = {})
      @connection = connection
      @migrator = Migrator.new(origin, connection, options)
      @options = options
      normalize_options(@options)
    end

    def set_session_lock_wait_timeouts
      global_innodb_lock_wait_timeout = @connection.select_one("SHOW GLOBAL VARIABLES LIKE 'innodb_lock_wait_timeout'")
      global_lock_wait_timeout = @connection.select_one("SHOW GLOBAL VARIABLES LIKE 'lock_wait_timeout'")

      if global_innodb_lock_wait_timeout
        desired_innodb_lock_wait_timeout = global_innodb_lock_wait_timeout['Value'].to_i + LOCK_WAIT_TIMEOUT_DELTA
        if desired_innodb_lock_wait_timeout <= INNODB_LOCK_WAIT_TIMEOUT_MAX
          @connection.execute("SET SESSION innodb_lock_wait_timeout=#{desired_innodb_lock_wait_timeout}")
        end
      end

      if global_lock_wait_timeout
        desired_lock_wait_timeout = global_lock_wait_timeout['Value'].to_i + LOCK_WAIT_TIMEOUT_DELTA
        if desired_lock_wait_timeout <= LOCK_WAIT_TIMEOUT_MAX
          @connection.execute("SET SESSION lock_wait_timeout=#{desired_lock_wait_timeout}")
        end
      end
    end

    def run
      set_session_lock_wait_timeouts
      migration = @migrator.run
      entangler = Entangler.new(migration, @connection)

      entangler.run do
        @options[:verifier] ||= Proc.new { |conn| triggers_still_exist?(conn, entangler) }
        Chunker.new(migration, @connection, @options).run
        raise "Required triggers do not exist" unless triggers_still_exist?(@connection, entangler)
        if @options[:atomic_switch]
          AtomicSwitcher.new(migration, @connection).run
        else
          LockedSwitcher.new(migration, @connection).run
        end
      end
    end

    def triggers_still_exist?(conn, entangler)
      triggers = conn.select_values("SHOW TRIGGERS LIKE '%#{migrator.origin.name}'").select { |name| name =~ /^lhmt/ }
      triggers.sort == entangler.expected_triggers.sort
    end

    private

    def normalize_options(options)
      Lhm.logger.info "Starting LHM run on table=#{@migrator.name}"

      unless options.include?(:atomic_switch)
        if supports_atomic_switch?
          options[:atomic_switch] = true
        else
          raise Error.new(
            "Using mysql #{version_string}. You must explicitly set " \
            'options[:atomic_switch] (re SqlHelper#supports_atomic_switch?)')
        end
      end

      if options[:throttler]
        throttler_options = options[:throttler_options] || {}
        options[:throttler] = Throttler::Factory.create_throttler(options[:throttler], throttler_options)
      else
        options[:throttler] = Lhm.throttler
      end

      Lhm.connection.retry_config = options[:retriable] || {}

    rescue => e
      Lhm.logger.error "LHM run failed with exception=#{e.class} message=#{e.message}"
      raise
    end
  end
end
