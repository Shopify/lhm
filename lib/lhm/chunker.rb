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

    # Keeps track of the speed by performing linear regression on the data on
    # the last X minutes.
    class Speedometer
      attr_reader :log

      def self.linregress(x, y)
        raise ArgumentError, "x and y not the same length" if x.length != y.length

        n = x.length
        xsum = 0
        ysum = 0
        xxsum = 0
        yysum = 0
        xysum = 0

        n.times do |i|
          xsum += x[i]
          ysum += y[i]
          xxsum += x[i] ** 2
          yysum += y[i] ** 2
          xysum += x[i] * y[i]
        end

        denom = (n * xxsum - xsum ** 2)
        if denom == 0
          return [0, 0, true]
        end

        slope = (n * xysum - xsum * ysum) / denom
        intercept = ysum / n - slope * xsum / n

        [slope, intercept, false]
      end

      def initialize(window, initial_value = 0)
        # log is just a list of [time, f(time)]
        @log = []

        # window is the window duration in seconds. Data outside of this window
        # will be discarded as more comes in.
        @window = window

        self << initial_value
      end

      def <<(ft)
        now = Time.now
        @log << [now, ft]

        # Find the first data point that's in the window. This data point may
        # be very close to the current time and therefore the majority of the
        # timed window may not have any data points in it.
        #
        # If we discarded all data points before this data point, the window is
        # thus more biased towards the present and hence may be an
        # over-estimate of the current speed. Thus, we keep just one data point
        # before of the window.
        i = @log.find_index { |l| now - l[0] < @window }
        i -= 1 if i > 0
        @log = @log[i..-1]
      end

      def speed
        return nil if @log.length < 2

        x = []
        y = []

        # Normalize all time entry to 0 otherwise it'll be too large and cause
        # wide inaccuracy.
        first_time = @log[0][0]

        @log.each do |entry|
          x << entry[0] - first_time
          y << entry[1]
        end

        slope, _, singular = self.class.linregress(x, y)
        return nil if singular
        slope
      end
    end

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
      @speedometer_window = options[:speedometer_window] || 5 * 60
    end

    def execute
      @start_time = Time.now

      return if @chunk_finder.table_empty?
      speedometer = Speedometer.new(@speedometer_window)

      next_to_insert = @start
      bytes_copied = 0
      while next_to_insert <= @limit || (@start == @limit)
        stride = @throttler.stride
        top = upper_id(next_to_insert, stride)
        verify_can_run

        affected_rows = ChunkInsert.new(@migration, @connection, next_to_insert, top, @retry_options).insert_and_return_count_of_rows_created
        expected_rows = top - next_to_insert + 1

        # Only log the chunker progress every 5 minutes instead of every iteration
        current_time = Time.now
        if current_time - @start_time > (5 * 60)
          Lhm.logger.info("Inserted #{affected_rows} rows into the destination table from #{next_to_insert} to #{top}")
          @start_time = current_time
        end

        if affected_rows < expected_rows
          raise_on_non_pk_duplicate_warning
        end

        p = progress

        additional_info = {
          total_bytes: p[0],
          bytes_copied: p[1],
        }

        bytes_copied += additional_info[:bytes_copied]
        speedometer << bytes_copied
        additional_info[:copy_speed] = speedometer.speed

        @printer.notify(next_to_insert, @limit, additional_info)

        if @throttler && affected_rows > 0
          @throttler.run
        end

        next_to_insert = top + 1
        break if @start == @limit
      end
      @printer.end
    rescue => e
      @printer.exception(e) if @printer.respond_to?(:exception)
      raise
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

    def verify_can_run
      return unless @verifier
      @retry_helper.with_retries(log_prefix: LOG_PREFIX) do |retriable_connection|
        raise "Verification failed, aborting early" if !@verifier.call(retriable_connection)
      end
    end

    def progress
      query = %W{
        SELECT
          (origin_table.data_length + origin_table.index_length) AS origin_size,
          (destination_table.data_length + destination_table.index_length) as destination_size
        FROM information_schema.tables AS destination_table
        JOIN information_schema.tables AS origin_table
          ON origin_table.table_name = '#{@migration.origin_name}'
        WHERE destination_table.table_name = '#{@migration.destination_name}'
      }
      @retry_helper.with_retries do |retriable_connection|
        retriable_connection.select_rows(query.join(' ')).first
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
