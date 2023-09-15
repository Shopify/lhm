# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

require 'lhm/table'
require 'lhm/migration'
require 'lhm/atomic_switcher'
require 'lhm/connection'

describe Lhm::AtomicSwitcher do
  include IntegrationHelper

  before(:each) { connect_master! }

  describe 'switching' do
    before(:each) do
      Thread.abort_on_exception = true
      @origin = table_create('origin')
      @destination = table_create('destination')
      @migration = Lhm::Migration.new(@origin, @destination)
      @logs = StringIO.new
      Lhm.logger = Logger.new(@logs)
      Lhm.progress = Lhm::Progress.new(@origin, connection)
      @connection.execute('SET GLOBAL innodb_lock_wait_timeout=3')
      @connection.execute('SET GLOBAL lock_wait_timeout=3')
    end

    after(:each) do
      Thread.abort_on_exception = false
    end

    it 'should retry and log on lock wait timeouts' do
      ar_connection = mock()
      ar_connection.stubs(:data_source_exists?).returns(true)
      ar_connection.stubs(:active?).returns(true)
      ar_connection.stubs(:execute).returns([["dummy"]], [["dummy"]], [["dummy"]])
                   .then
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction.')
                   .then
                   .returns([["dummy"]]) # Matches initial host -> triggers retry

      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          tries: 3,
          base_interval: 0
        }
      })

      switcher = Lhm::AtomicSwitcher.new(@migration, connection)

      assert switcher.run

      log_messages = @logs.string.split("\n")
      assert_equal(2, log_messages.length)
      assert log_messages[0].include? "Starting run of class=Lhm::AtomicSwitcher"
      # On failure of this assertion, check for Lhm::Connection#file
      assert log_messages[1].include? "[AtomicSwitcher] ActiveRecord::StatementInvalid: 'Lock wait timeout exceeded; try restarting transaction.' - 1 tries"
    end

    it 'should give up on lock wait timeouts after a configured number of tries' do
      ar_connection = mock()
      ar_connection.stubs(:data_source_exists?).returns(true)
      ar_connection.stubs(:active?).returns(true)
      ar_connection.stubs(:execute).returns([["dummy"]], [["dummy"]], [["dummy"]])
                   .then
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction.')
                   .then
                   .returns([["dummy"]]) # triggers retry 1
                   .then
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction.')
                   .then
                   .returns([["dummy"]]) # triggers retry 2
                   .then
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction.') # triggers retry 2

      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          tries: 2,
          base_interval: 0
        }
      })

      switcher = Lhm::AtomicSwitcher.new(@migration, connection)

      assert_raises(ActiveRecord::StatementInvalid) { switcher.run }
    end

    it 'should raise on non lock wait timeout exceptions' do
      switcher = Lhm::AtomicSwitcher.new(@migration, connection)
      switcher.send :define_singleton_method, :atomic_switch do
        'SELECT * FROM nonexistent'
      end
      value(-> { switcher.run }).must_raise(ActiveRecord::StatementInvalid)
    end

    it "should raise when destination doesn't exist" do
      ar_connection = mock()
      ar_connection.stubs(:data_source_exists?).returns(false)

      connection = Lhm::Connection.new(connection: ar_connection)

      switcher = Lhm::AtomicSwitcher.new(@migration, connection)

      assert_raises(Lhm::Error) { switcher.run }
    end

    it 'rename origin to archive' do
      switcher = Lhm::AtomicSwitcher.new(@migration, connection)
      switcher.run

      replica do
        value(data_source_exists?(@origin)).must_equal true
        value(table_read(@migration.archive_name).columns.keys).must_include 'origin'
      end
    end

    it 'rename destination to origin' do
      switcher = Lhm::AtomicSwitcher.new(@migration, connection)
      switcher.run

      replica do
        value(data_source_exists?(@destination)).must_equal false
        value(table_read(@origin.name).columns.keys).must_include 'destination'
      end
    end
  end
end
