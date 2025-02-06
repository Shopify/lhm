require 'retriable'
require 'lhm/sql_helper'
require 'lhm/proxysql_helper'

module Lhm
  # SqlRetry standardizes the interface for retry behavior in components like
  # Entangler, AtomicSwitcher, ChunkerInsert.
  #
  # By default if an error includes the message "Lock wait timeout exceeded", or
  # "Deadlock found when trying to get lock", SqlRetry will retry again
  # once the MySQL client returns control to the caller, plus one second.
  # It will retry a total of 10 times and output to the logger a description
  # of the retry with error information, retry count, and elapsed time.
  #
  # This behavior can be modified by passing `options` that are documented in
  # https://github.com/kamui/retriable. Additionally, a "log_prefix" option,
  # which is unique to SqlRetry can be used to prefix log output.
  class SqlRetry
    RECONNECT_SUCCESSFUL_MESSAGE = "LHM successfully reconnected to initial host:"
    CLOUDSQL_VERSION_COMMENT = "(Google)"
    # Will retry for 120 seconds (approximately, since connecting takes time).
    RECONNECT_RETRY_MAX_ITERATION = 120
    RECONNECT_RETRY_INTERVAL = 1
    # Will abort the LHM if it had to reconnect more than 25 times in a single run (indicator that there might be
    # something wrong with the network and would be better to run the LHM at a later time).
    RECONNECTION_MAXIMUM = 25

    MYSQL_VAR_NAMES = {
      hostname: "@@global.hostname",
      server_id: "@@global.server_id",
      version_comment: "@@version_comment",
    }

    def initialize(connection, retry_options: {}, reconnect_with_consistent_host: false)
      @connection = connection
      self.retry_config = retry_options
      self.reconnect_with_consistent_host = reconnect_with_consistent_host
    end

    # Complete explanation of algorithm: https://github.com/Shopify/lhm/pull/112
    def with_retries(log_prefix: nil)
      @log_prefix = log_prefix || "" # No prefix. Just logs

      # Amount of time LHM had to reconnect. Aborting if more than RECONNECTION_MAXIMUM
      reconnection_counter = 0

      Retriable.retriable(@retry_config) do
        # Using begin -> rescue -> end for Ruby 2.4 compatibility
        begin
          if @reconnect_with_consistent_host
            raise Lhm::Error.new("MySQL host has changed since the start of the LHM. Aborting to avoid data-loss") unless same_host_as_initial?
          end

          yield(@connection)
        rescue StandardError => e
          # Not all errors should trigger a reconnect. Some errors such be raised and abort the LHM (such as reconnecting to the wrong host).
          # The error will be raised the connection is still active (i.e. no need to reconnect) or if the connection is
          # dead (i.e. not active) and @reconnect_with_host is false (i.e. instructed not to reconnect)
          raise e if @connection.active? || (!@connection.active? && !@reconnect_with_consistent_host)

          # Lhm could be stuck in a weird state where it loses connection, reconnects and re looses-connection instantly
          # after, creating an infinite loop (because of the usage of `retry`). Hence, abort after 25 reconnections
          raise Lhm::Error.new("LHM reached host reconnection max of #{RECONNECTION_MAXIMUM} times. " \
            "Please try again later.") if reconnection_counter > RECONNECTION_MAXIMUM

          reconnection_counter += 1
          if reconnect_with_host_check!
            retry
          else
            raise Lhm::Error.new("LHM tried the reconnection procedure but failed. Aborting")
          end
        end
      end
    end

    # Both attributes will have defined setters
    attr_reader :retry_config, :reconnect_with_consistent_host
    attr_accessor :connection

    def retry_config=(retry_options)
      @retry_config = default_retry_config.dup.merge!(retry_options)
    end

    def reconnect_with_consistent_host=(reconnect)
      if (@reconnect_with_consistent_host = reconnect)
        @initial_hostname = hostname
        @initial_server_id = server_id
      end
    end

    private

    def hostname
      mysql_single_value(MYSQL_VAR_NAMES[:hostname])
    end

    def server_id
      mysql_single_value(MYSQL_VAR_NAMES[:server_id])
    end

    def cloudsql?
      mysql_single_value(MYSQL_VAR_NAMES[:version_comment]).include?(CLOUDSQL_VERSION_COMMENT)
    end

    def mysql_single_value(name)
      query = Lhm::ProxySQLHelper.tagged("SELECT #{name} LIMIT 1")

      @connection.select_value(query)
    end

    def same_host_as_initial?
      return @initial_server_id == server_id if cloudsql?
      @initial_hostname == hostname
    end

    def log_with_prefix(message, level = :info)
      message.prepend("[#{@log_prefix}] ") if @log_prefix
      Lhm.logger.public_send(level, message)
    end

    def reconnect_with_host_check!
      log_with_prefix("Lost connection to MySQL, will retry to connect to same host")

      RECONNECT_RETRY_MAX_ITERATION.times do
        begin
          sleep(RECONNECT_RETRY_INTERVAL)

          # tries to reconnect. On failure will trigger a retry
          @connection.reconnect!

          if same_host_as_initial?
            # This is not an actual error, but controlled way to get the parent `Retriable.retriable` to retry
            # the statement that failed (since the Retriable gem only retries on errors).
            log_with_prefix("LHM successfully reconnected to initial host: #{@initial_hostname} (server_id: #{@initial_server_id})")
            return true
          else
            # New Master --> abort LHM (reconnecting will not change anything)
            log_with_prefix("Reconnected to wrong host. Started migration on: #{@initial_hostname} (server_id: #{@initial_server_id}), but reconnected to: #{hostname} (server_id: #{server_id}).", :error)
            return false
          end
        rescue ActiveRecord::ConnectionNotEstablished
          # Retry if ActiveRecord cannot reach host
          next
        rescue StandardError => e
          log_with_prefix("Encountered error: [#{e.class}] #{e.message}. Will stop reconnection procedure.", :info)
          return false
        end
      end

      false
    end

    # For a full list of configuration options see https://github.com/kamui/retriable
    def default_retry_config
      {
        on: retriable_mysql2_errors || retriable_trilogy_errors,
        multiplier: 1, # each successive interval grows by this factor
        base_interval: 1, # the initial interval in seconds between tries.
        tries: 20, # Number of attempts to make at running your code block (includes initial attempt).
        rand_factor: 0, # percentage to randomize the next retry interval time
        max_elapsed_time: Float::INFINITY, # max total time in seconds that code is allowed to keep being retried
        on_retry: Proc.new do |exception, try_number, total_elapsed_time, next_interval|
          log_with_prefix("#{exception.class}: '#{exception.message}' - #{try_number} tries in #{total_elapsed_time} seconds and #{next_interval} seconds until the next try.", :error)
        end
      }.freeze
    end

    def retriable_mysql2_errors
      return unless defined?(Mysql2::Error)

      {
        StandardError => [
          /Lock wait timeout exceeded/,
          /Timeout waiting for a response from the last query/,
          /Deadlock found when trying to get lock/,
          /Query execution was interrupted/,
          /Lost connection to MySQL server during query/,
          /Max connect timeout reached/,
          /Unknown MySQL server host/,
          /connection is locked to hostgroup/,
          /The MySQL server is running with the --read-only option so it cannot execute this statement/,
        ],
      }
    end

    def retriable_trilogy_errors
      return unless defined?(Trilogy::BaseError)

      errors = {
        ActiveRecord::StatementInvalid => [
          /Lock wait timeout exceeded/,
          /Timeout waiting for a response from the last query/,
          /Deadlock found when trying to get lock/,
          /Query execution was interrupted/,
          /Lost connection to MySQL server during query/,
          /Max connect timeout reached/,
          /Unknown MySQL server host/,
          /connection is locked to hostgroup/,
          /The MySQL server is running with the --read-only option so it cannot execute this statement/,
        ],
        Trilogy::ConnectionError => nil,
        Trilogy::TimeoutError => nil,
      }

      if ActiveRecord::VERSION::STRING >= "7.1"
        errors[ActiveRecord::ConnectionFailed] = nil
      end

      errors
    end
  end
end
