# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/chunker'
require 'lhm/entangler'
require 'lhm/atomic_switcher'
require 'lhm/locked_switcher'
require 'lhm/migrator'
require 'lhm/verifier'

module Lhm
  # Copies an origin table to an altered destination table. Live activity is
  # synchronized into the destination table using triggers.
  #
  # Once the origin and destination tables have converged, origin is archived
  # and replaced by destination.
  class Invoker
    include SqlHelper
    LOCK_WAIT_TIMEOUT_DELTA = -2

    attr_reader :migrator, :connection

    def initialize(origin, connection, options)
      @connection = connection
      @migrator = Migrator.new(origin, connection, options)
    end

    def set_session_lock_wait_timeouts
      global_innodb_lock_wait_timeout = @connection.execute("SHOW GLOBAL VARIABLES LIKE 'innodb_lock_wait_timeout'").first.last.to_i
      global_lock_wait_timeout = @connection.execute("SHOW GLOBAL VARIABLES LIKE 'lock_wait_timeout'").first.last.to_i

      unless safe_to_run?(global_innodb_lock_wait_timeout, global_lock_wait_timeout)
        raise "The value of lock_wait_timeout: #{global_lock_wait_timeout} or innodb_lock_wait_timeout: #{global_innodb_lock_wait_timeout} is less than the absolute value of the delta #{LOCK_WAIT_TIMEOUT_DELTA.abs}, it is unsafe to run this LHM" 
      end

      @connection.execute("SET SESSION innodb_lock_wait_timeout=#{global_innodb_lock_wait_timeout + LOCK_WAIT_TIMEOUT_DELTA}") 
      @connection.execute("SET SESSION lock_wait_timeout=#{global_lock_wait_timeout + LOCK_WAIT_TIMEOUT_DELTA}")
    end

    def safe_to_run?(global_innodb_lock_wait_timeout, global_lock_wait_timeout)
      global_lock_wait_timeout > LOCK_WAIT_TIMEOUT_DELTA.abs && global_innodb_lock_wait_timeout > LOCK_WAIT_TIMEOUT_DELTA.abs
    end

    def run(options = {})
      options[:verify] ||= false

      Lhm.logger.info "Starting LHM run on table=#{@migrator.name}"

      if !options.include?(:atomic_switch)
        if supports_atomic_switch?
          options[:atomic_switch] = true
        else
          raise Error.new(
            "Using mysql #{version_string}. You must explicitly set " +
            "options[:atomic_switch] (re SqlHelper#supports_atomic_switch?)")
        end
      end

      set_session_lock_wait_timeouts

      if options[:verify]
        verifier = Verifier.new(@migrator, @connection)
        verifier.risk
      else
        migration = @migrator.run

        Entangler.new(migration, @connection).run do
          Chunker.new(migration, @connection, options).run
          if options[:atomic_switch]
            AtomicSwitcher.new(migration, @connection).run
          else
            LockedSwitcher.new(migration, @connection).run
          end
        end
      end

    rescue => e
      Lhm.logger.error "LHM run failed with exception=#{e.class} message=#{e.message}"
      raise
    end
  end
end
