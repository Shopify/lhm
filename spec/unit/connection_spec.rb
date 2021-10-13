require 'lhm/connection'

describe Lhm::Connection do

  LOCK_WAIT = ActiveRecord::StatementInvalid.new('Lock wait timeout exceeded; try restarting transaction.')

  before(:each) do
    @logs = StringIO.new
    Lhm.logger = Logger.new(@logs)
  end

  it "Should find use calling file as prefix" do
    ar_connection = mock()
    ar_connection.stubs(:execute).raises(LOCK_WAIT).then.returns(true)

    connection = Lhm::Connection.new(connection: ar_connection)

    connection.execute("SHOW TABLES", { base_interval: 0 })

    log_messages = @logs.string.split("\n")
    assert_equal(1, log_messages.length)
    assert log_messages.first.include?("[ConnectionSpec]")
  end

  it "#execute should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:execute).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns(true)

    connection = Lhm::Connection.new(connection: ar_connection)

    connection.execute("SHOW TABLES", { base_interval: 0, tries: 3 })

    log_messages = @logs.string.split("\n")
    assert_equal(2, log_messages.length)
  end

  it "#update should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:update).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns(1)

    connection = Lhm::Connection.new(connection: ar_connection)

    val = connection.update("SHOW TABLES", { base_interval: 0, tries: 3 })

    log_messages = @logs.string.split("\n")
    assert_equal val, 1
    assert_equal(2, log_messages.length)
  end

  it "#select_value should be retried" do
    ar_connection = mock()
    ar_connection.stubs(:select_value).raises(LOCK_WAIT)
                 .then.raises(LOCK_WAIT)
                 .then.returns("dummy")

    connection = Lhm::Connection.new(connection: ar_connection)

    val = connection.select_value("SHOW TABLES", { base_interval: 0, tries: 3 })

    log_messages = @logs.string.split("\n")
    assert_equal val, "dummy"
    assert_equal(2, log_messages.length)
  end
end