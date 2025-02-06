require 'minitest/autorun'
require 'integration/sql_retry/lock_wait_timeout_test_helper'
require 'lhm'

describe Lhm::SqlRetry do
  before(:each) do
    @old_logger = Lhm.logger
    @logger = StringIO.new
    Lhm.logger = Logger.new(@logger)

    @helper = LockWaitTimeoutTestHelper.new(
      lock_duration: 5,
      innodb_lock_wait_timeout: 2
    )

    @helper.create_table_to_lock

    # Start a thread to hold a lock on the table
    @locked_record_id = @helper.hold_lock

    # Assert our pre-conditions
    assert_equal 2, @helper.record_count

    DATABASE.client.any_instance.stubs(:active?).returns(true)
  end

  after(:each) do
    # Restore default logger
    Lhm.logger = @old_logger
  end

  # This is the control test case. It shows that when Lhm::SqlRetry is not used,
  # a lock wait timeout exceeded error is raised.
  it "does nothing to prevent exceptions, when not used" do
    puts ""
    puts "***The output you see below is OK so long as the test passes.***"
    puts "*" * 64
    # Start a thread to retry, once the lock is held, execute the block
    @helper.with_waiting_lock do |waiting_connection|
      @helper.insert_records_at_ids(waiting_connection, [@locked_record_id])
    end

    exception = assert_raises { @helper.trigger_wait_lock }

    assert_match Regexp.new("Lock wait timeout exceeded; try restarting transaction"), exception.message
    assert_equal DATABASE.timeout_error, exception.class

    assert_equal 2, @helper.record_count # no records inserted
    puts "*" * 64
  end

  # This is test demonstrating the happy path: a well configured retry
  # tuned to the locks it encounters.
  it "successfully executes the SQL despite the errors encountered" do
    # Start a thread to retry, once the lock is held, execute the block
    @helper.with_waiting_lock do |waiting_connection|
      sql_retry = Lhm::SqlRetry.new(waiting_connection, retry_options: {
        base_interval: 0.2, # first retry after 200ms
        multiplier: 1, # subsequent retries wait 1x longer than first retry (no change)
        tries: 3, # we only need 3 tries (including the first) for the scenario described below
        rand_factor: 0 # do not introduce randomness to wait timer
      }, reconnect_with_consistent_host: false)

      # RetryTestHelper is configured to hold lock for 5 seconds and timeout after 2 seconds.
      # Therefore the sequence of events will be:
      # 0s:   first insert query is started while lock is held
      # 2s:   first timeout error will occur, SqlRetry is configured to wait 200ms after this
      # 2.2s: second insert query is started while lock is held
      # 4.2s: second timeout error will occur, SqlRetry is configured to wait 200ms after this
      # 4.4s: third insert query is started while lock is held
      # 5s:   lock is released, insert successful no further retries needed
      sql_retry.with_retries do |retriable_connection|
        @helper.insert_records_at_ids(retriable_connection, [@locked_record_id])
      end
    end

    @helper.trigger_wait_lock

    assert_equal 3, @helper.record_count # records inserted successfully despite lock

    logs = @logger.string.split("\n")
    assert_equal 2, logs.length

    assert logs.first.include?("Lock wait timeout exceeded; try restarting transaction")
    assert logs.first.include?("- 1 tries")
    assert logs.first.include?("0.2 seconds until the next try")

    assert logs.last.include?("Lock wait timeout exceeded; try restarting transaction")
    assert logs.last.include?("- 2 tries")
    assert logs.last.include?("0.2 seconds until the next try")
  end

  # This is test demonstrating the sad configuration path: it shows
  # that when the retries are not tuned to the locks encountered,
  # retries are not effective.
  it "fails to retry enough to overcome the timeout" do
    puts ""
    puts "***The output you see below is OK so long as the test passes.***"
    puts "*" * 64
    # Start a thread to retry, once the lock is held, execute the block
    @helper.with_waiting_lock do |waiting_connection|
      sql_retry = Lhm::SqlRetry.new(waiting_connection, retry_options: {
        base_interval: 0.2, # first retry after 200ms
        multiplier: 1, # subsequent retries wait 1x longer than first retry (no change)
        tries: 2, # we need 3 tries (including the first) for the scenario described below, but we only get two...we will fail
        rand_factor: 0 # do not introduce randomness to wait timer
      }, reconnect_with_consistent_host: false)

      # RetryTestHelper is configured to hold lock for 5 seconds and timeout after 2 seconds.
      # Therefore the sequence of events will be:
      # 0s:   first insert query is started while lock is held
      # 2s:   first timeout error will occur, SqlRetry is configured to wait 200ms after this
      # 2.2s: second insert query is started while lock is held
      # 4.2s: second timeout error will occur, SqlRetry is configured to only try twice, so we fail here
      sql_retry.with_retries do |retriable_connection|
        @helper.insert_records_at_ids(retriable_connection, [@locked_record_id])
      end
    end

    exception = assert_raises { @helper.trigger_wait_lock }

    assert_match Regexp.new("Lock wait timeout exceeded; try restarting transaction"), exception.message
    assert_equal DATABASE.timeout_error, exception.class

    assert_equal 2, @helper.record_count # no records inserted
    puts "*" * 64
  end
end
