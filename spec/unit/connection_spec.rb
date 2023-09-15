require 'lhm/connection'
require 'lhm/proxysql_helper'

describe Lhm::Connection do

  LOCK_WAIT = ActiveRecord::StatementInvalid.new('Lock wait timeout exceeded; try restarting transaction.')

  before(:each) do
    @logs = StringIO.new
    Lhm.logger = Logger.new(@logs)
  end

  it "Should find use calling file as prefix" do
    ar_connection = mock()
    ar_connection.stubs(:execute).raises(LOCK_WAIT).then.returns(true)
    ar_connection.stubs(:active?).returns(true)

    connection = Lhm::Connection.new(connection: ar_connection, options: {
      retriable: {
        base_interval: 0
      }
    })

    connection.execute("SHOW TABLES", should_retry: true)

    log_messages = @logs.string.split("\n")
    assert_equal(1, log_messages.length)
    assert log_messages.first.include?("[ConnectionSpec]")
  end

  it "#execute should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:execute).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns(true)
    ar_connection.stubs(:active?).returns(true)

    connection = Lhm::Connection.new(connection: ar_connection, options: {
      retriable: {
        base_interval: 0,
        tries: 3
      }
    })

    connection.execute("SHOW TABLES", should_retry: true)

    log_messages = @logs.string.split("\n")
    assert_equal(2, log_messages.length)
  end

  it "#update should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:update).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns(1)
    ar_connection.stubs(:active?).returns(true)

    connection = Lhm::Connection.new(connection: ar_connection, options: {
      retriable: {
        base_interval: 0,
        tries: 3
      }
    })

    val = connection.update("SHOW TABLES", should_retry: true)

    log_messages = @logs.string.split("\n")
    assert_equal val, 1
    assert_equal(2, log_messages.length)
  end

  it "#select_value should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:select_value).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns("dummy")
    ar_connection.stubs(:active?).returns(true)

    connection = Lhm::Connection.new(connection: ar_connection, options: {
      retriable: {
        base_interval: 0,
        tries: 3
      }
    })

    val = connection.select_value("SHOW TABLES", should_retry: true)

    log_messages = @logs.string.split("\n")
    assert_equal val, "dummy"
    assert_equal(2, log_messages.length)
  end

  it "Queries should be tagged with ProxySQL tag if reconnect_with_consistent_host is enabled" do
    ar_connection = mock()
    ar_connection.expects(:public_send).with(:select_value, "SHOW TABLES #{Lhm::ProxySQLHelper::ANNOTATION}").returns("dummy")
    ar_connection.stubs(:execute).times(4).returns([["dummy"]])
    ar_connection.stubs(:active?).returns(true)

    connection = Lhm::Connection.new(connection: ar_connection, options: {
      reconnect_with_consistent_host: true,
      retriable: {
        base_interval: 0,
        tries: 3
      }
    })

    val = connection.select_value("SHOW TABLES", should_retry: true)

    assert_equal val, "dummy"
  end
end
