# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'lhm/command'
require 'lhm/sql_helper'
require 'lhm/chunk_insert'
require 'lhm/chunk_finder'

module Lhm
  class Chunker
    include Command
    include SqlHelper

    attr_reader :connection

    LOG_PREFIX = "Chunker"

    # Copy from origin to destination in chunks of size `stride`.
    # Use the `throttler` class to sleep between each stride.
    def initialize(migration, connection = nil, options = {})
      @migration = migration
      @connection = connection
      @chunk_finder = ChunkFinder.new(migration, connection, options)
      @options = options
      @raise_on_warnings = options.fetch(:raise_on_warnings, false)
      @verifier = options[:verifier]
      if @throttler = options[:throttler]
        @throttler.connection = @connection if @throttler.respond_to?(:connection=)
      end
      @start = @chunk_finder.start
      @limit = @chunk_finder.limit
      @printer = options[:printer] || Printer::Percentage.new
      @retry_options = options[:retriable] || {}
      @retry_helper = SqlRetry.new(
        @connection,
        retry_options: @retry_options
      )
    end

    def execute
      start_time = Time.now

      return if @chunk_finder.table_empty?
      Lhm.progress.update_before_copy(@chunk_finder.start, @chunk_finder.limit)

      @next_to_insert = @start
      while @next_to_insert <= @limit || (@start == @limit)
        stride = @throttler.stride
        top = upper_id(@next_to_insert, stride)
        verify_can_run

        affected_rows = ChunkInsert.new(@migration, @connection, bottom, top, @retry_options).insert_and_return_count_of_rows_created
        expected_rows = top - bottom + 1

        # Only log the chunker progress every 1 minute instead of every iteration
        current_time = Time.now
        if current_time - start_time > 60
          Lhm.logger.info("Inserted #{Lhm.progress.rows_written} rows into the destination table 
            upto #{top} with a speed of #{Lhm.progress.copy_speed}")
          start_time = current_time
        end

        if affected_rows < expected_rows
          raise_on_non_pk_duplicate_warning
        end

        if @throttler && affected_rows > 0
          @throttler.run
        end

        @next_to_insert = top + 1
        @printer.notify(bottom, @limit)
        Lhm.progress.update_during_copy(affected_rows)

        break if @start == @limit
      end
      @printer.end
    rescue => e
      @printer.exception(e) if @printer.respond_to?(:exception)
      raise
    end

    def update_state_before_execute
      Lhm.progress.update_state(Lhm::STATE_COPYING)
    end

    def update_state_after_execute
      Lhm.progress.update_state(Lhm::STATE_COPYING_DONE)
    end

    def update_state_when_revert
      Lhm.progress.update_state(Lhm::STATE_COPYING_FAILED)
    end

    private

    def raise_on_non_pk_duplicate_warning
      @connection.execute("show warnings", should_retry: true, log_prefix: LOG_PREFIX).each do |level, code, message|
        unless message.match?(/Duplicate entry .+ for key 'PRIMARY'/)
          m = "Unexpected warning found for inserted row: #{message}"
          Lhm.logger.warn(m)
          raise Error.new(m) if @raise_on_warnings
        end
      end
    end

    def bottom
      @next_to_insert
    end

    def verify_can_run
      return unless @verifier
      @retry_helper.with_retries(log_prefix: LOG_PREFIX) do |retriable_connection|
        raise "Verification failed, aborting early" if !@verifier.call(retriable_connection)
      end
    end

    def upper_id(next_id, stride)
      sql = "select id from `#{ @migration.origin_name }` where id >= #{ next_id } order by id limit 1 offset #{ stride - 1}"
      top = @connection.select_value(sql, should_retry: true, log_prefix: LOG_PREFIX)

      [top ? top.to_i : @limit, @limit].min
    end

    def validate
      return if @chunk_finder.table_empty?
      @chunk_finder.validate
    end
  end
end
