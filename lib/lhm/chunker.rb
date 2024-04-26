# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'lhm/command'
require 'lhm/sql_helper'
require 'lhm/printer'
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
      @ignore_warning_regexps = [/Duplicate entry .+ for key '(#{@migration.destination_name}\.)?PRIMARY'/]
      @ignore_warning_regexps.concat(options.fetch(:ignore_warning_regexps, []))
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
      @start_time = Time.now

      return if @chunk_finder.table_empty?
      @next_to_insert = @start
      while @next_to_insert <= @limit || (@start == @limit)
        stride = @throttler.stride
        top = upper_id(@next_to_insert, stride)
        verify_can_run

        affected_rows = ChunkInsert.new(@migration, @connection, bottom, top, @retry_options).insert_and_return_count_of_rows_created
        expected_rows = top - bottom + 1

        # Only log the chunker progress every 5 minutes instead of every iteration
        current_time = Time.now
        if current_time - @start_time > (5 * 60)
          Lhm.logger.info("Inserted #{affected_rows} rows into the destination table from #{bottom} to #{top}")
          @start_time = current_time
        end

        if affected_rows < expected_rows
          raise_on_warning
        end

        if @throttler && affected_rows > 0
          @throttler.run
        end

        @next_to_insert = top + 1
        @printer.notify(bottom, @limit)

        break if @start == @limit
      end
      @printer.end
    rescue => e
      @printer.exception(e) if @printer.respond_to?(:exception)
      raise
    end

    private

    def raise_on_warning
      @connection.select_all("SHOW WARNINGS", should_retry: true, log_prefix: LOG_PREFIX).each do |row|
        next if @ignore_warning_regexps.any? { |regexp| row["Message"].match?(regexp) }

        m = "Unexpected warning found for inserted row: #{row["Message"]}"
        Lhm.logger.warn(m)
        raise Error.new(m) if @raise_on_warnings
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
      sql = "SELECT id FROM `#{ @migration.origin_name }` WHERE id >= #{ next_id } ORDER BY id LIMIT 1 OFFSET #{ stride - 1}"
      top = @connection.select_value(sql, should_retry: true, log_prefix: LOG_PREFIX)

      [top ? top.to_i : @limit, @limit].min
    end

    def validate
      return if @chunk_finder.table_empty?
      @chunk_finder.validate
    end

  end
end
