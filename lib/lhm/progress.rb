require 'lhm/printer'
require "json"

module Lhm
  STATE_COPYING = "copying"
  STATE_COPYING_DONE = "copying_done"
  STATE_COPYING_FAILED = "copying_failed"
  STATE_INITIAL = "initial"
  STATE_SETUP_FAILED = "setup_failed"
  STATE_SETUP_DONE = "setup_done"
  STATE_SWITCHING_TABLES = "switching_tables"
  STATE_SWITCHED_TABLES = "switched_tables"
  STATE_SWITCHING_TABLES_FAILED = "switching_tables_failed"
  STATE_TRIGGERS_DROPPED = "triggers_dropped"

  class Progress
    def initialize(origin, connection = nil, options: {})
      @origin = origin
      @connection = connection
      @options = options
      @throttler = options.include?(:throttler) ? options[:throttler].class.name : "None"
      @table_switcher = options.include?(:atomic_switch) ? "AtomicSwitcher" : "LockedSwitcher"
      @state = Lhm::STATE_INITIAL
      @printer = options[:printer] || Printer::Percentage.new
  
      @rows_written = 0    
      @speedometer_window = options[:speedometer_window] || 5 * 60
      @speedometer = Speedometer.new(@speedometer_window)
      @copy_speed = 0.0
      @bytes_copied = 0
      @avg_row_length = 0
      @total_bytes = 0
      @completion_percentage = 0
      @start_time = Time.now

      @retry_helper = SqlRetry.new(
        @connection,
        {
          log_prefix: "Progress"
        }.merge!(options.fetch(:retriable, {}))
      )
    end

    attr_reader :state, :completion_percentage, :rows_written, :copy_speed

    def update_before_copy(start, limit)
      populate_table_stats
      @min_pk_key = start
      @max_pk_key = limit
    end

    def update_during_copy(affected_rows)
      @rows_written += affected_rows

      @bytes_copied = @rows_written * @avg_row_length
      @completion_percentage = ((rows_written / @max_pk_key.to_f) * 100.0).round(2)
    
      @speedometer << @bytes_copied
      @copy_speed = @speedometer.speed

      current_time = Time.now
      if (current_time - @start_time > 60) || @options.include?(:verbose_logging)
        @printer.notify_progress(as_hash)
        @start_time = current_time
      end
    end

    def update_state(state)
      @completion_percentage = 100 if state == Lhm::STATE_COPYING_DONE

      @state = state
      @printer.notify_progress(as_hash)
    end

    def as_hash
      {
        "state" => @state,
        "version" => Lhm::VERSION,
        "source_table" => @origin.name,
        "destination_table" => @origin.destination_name,
        "throttler" => @throttler,
        "table_switcher" => @table_switcher,
        "avg_row_length" => "#{@avg_row_length} bytes",
        "estimated_bytes_copied" => @bytes_copied,
        "estimated_total_bytes" => @total_bytes,
        "completion_percentage" => "#{@completion_percentage}% complete",
        "estimated_copy_speed" => "#{@copy_speed} bytes/sec",
        "min_pk_key" => @min_pk_key,
        "max_pk_key" => @max_pk_key,
        "rows_written" => @rows_written,
      }
    end

    private

    def populate_table_stats
      table_stats = get_table_stats_from_information_schema
      @avg_row_length = table_stats[0]
      @total_bytes = table_stats[1]
    end

    def get_table_stats_from_information_schema
      query = %W{
        SELECT
          avg_row_length, (data_length + index_length)
        FROM information_schema.tables
        WHERE table_schema = '#{@connection.current_database}'
        AND table_name = '#{@origin.name}'
      }
      @retry_helper.with_retries do |retriable_connection|
        retriable_connection.select_rows(query.join(' ')).first
      end
    end

    # Speedometer is used to calculate the speed at which LHM is copying rows from source to the destination table. 
    # Taken from the PR authored by @shuhaowu from here - https://github.com/Shopify/lhm/pull/83. 
    class Speedometer
      attr_reader :log

      def self.linregress(x, y)
        raise ArgumentError, "x and y not the same length" if x.length != y.length

        n = x.length
        xsum = 0.0
        ysum = 0.0
        xxsum = 0.0
        yysum = 0.0
        xysum = 0.0

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
        slope.round(2)
      end
    end
  end
end
