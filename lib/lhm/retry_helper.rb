require 'retriable'
require 'lhm/sql_helper'

module Lhm
  # RetryHelper standardizes the interface for retry behavior in components like
  # Entangler, AtomicSwitcher, ChunkerInsert.
  #
  # To retry some behavior, use `connection_with_retries(statement: sql, invoke_with: :execute)`.
  # Retry helper assumes:
  # * `@connection` is available
  # * `configure_retry` is called before `connection_with_retries` is used
  #
  # If an error includes the message "Lock wait timeout exceeded",
  # the RetryHelper will retry the SQL command again after about 500ms
  # for up to one hour.
  #
  # This behavior can be modified by calling `configure_retry` with options described in
  # https://github.com/kamui/retriable
  module RetryHelper
    def connection_with_retries(statement:, invoke_with:)
      Retriable.retriable(retry_config) do
        @connection.public_send(invoke_with, SqlHelper.tagged(statement))
      end
    end

    def configure_retry(options)
      @retry_config = DEFAULT_RETRY_CONFIG.dup
      @retry_config.merge!(options) if options
    end

    attr_reader :retry_config

    private

    # For a full list of configuration options see https://github.com/kamui/retriable
    DEFAULT_RETRY_CONFIG = {
      on: {
        StandardError => [/Lock wait timeout exceeded/]
      },
      multiplier: 1, # each successive interval grows by this factor
      base_interval: 0.5, # the initial interval in seconds between tries.
      tries: 7200, # Number of attempts to make at running your code block (includes initial attempt).
      rand_factor: 0.25, # percentage to randomize the next retry interval time
      max_elapsed_time: Float::INFINITY, # max total time in seconds that code is allowed to keep being retried
      on_retry: Proc.new do |exception, try, elapsed_time, next_interval|
        Lhm.logger.info("#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try.")
      end
    }.freeze
  end
end
