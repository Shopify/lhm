# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'lhm/table'
require 'lhm/migration'

describe Lhm::Chunker do
  include IntegrationHelper

  before(:each) { connect_master! }

  let(:error_key) do
    if mysql_version.start_with?("8")
      "custom_primary_key_dest.index_custom_primary_key_on_id"
    else
      "index_custom_primary_key_on_id"
    end
  end

  describe 'copying' do
    before(:each) do
      @origin = table_create(:origin)
      @destination = table_create(:destination)
      @migration = Lhm::Migration.new(@origin, @destination)
      @logs = StringIO.new
      Lhm.logger = Logger.new(@logs)
    end

    def log_messages
      @logs.string.split("\n")
    end

    it 'should copy 1 row from origin to destination even if the id of the single row does not start at 1' do
      execute("insert into origin set id = 1001 ")

      Lhm::Chunker.new(@migration, connection, {throttler: throttler, printer: printer} ).run

      replica do
        value(count_all(@destination.name)).must_equal(1)
      end

    end

    it 'should copy and ignore duplicate primary key' do
      execute("insert into origin set id = 1001 ")
      execute("insert into origin set id = 1002 ")
      execute("insert into destination set id = 1002 ")

      Lhm::Chunker.new(@migration, connection, {throttler: throttler, printer: printer} ).run

      replica do
        value(count_all(@destination.name)).must_equal(2)
      end
    end

    it 'should copy and ignore duplicate composite primary key' do
      origin = table_create(:composite_primary_key)
      destination = table_create(:composite_primary_key_dest)
      migration = Lhm::Migration.new(origin, destination)

      execute("insert into composite_primary_key set id = 1001, shop_id = 1")
      execute("insert into composite_primary_key set id = 1002, shop_id = 1")
      execute("insert into composite_primary_key_dest set id = 1002, shop_id = 1")

      Lhm::Chunker.new(migration, connection, {throttler: throttler, printer: printer} ).run

      replica do
        value(count_all(destination.name)).must_equal(2)
      end
    end

    it 'should copy and raise on unexpected warnings' do
      origin = table_create(:custom_primary_key)
      destination = table_create(:custom_primary_key_dest)
      migration = Lhm::Migration.new(origin, destination)

      execute("insert into custom_primary_key set id = 1001, pk = 1")
      execute("insert into custom_primary_key_dest set id = 1001, pk = 2")

      exception = assert_raises(Lhm::Error) do
        Lhm::Chunker.new(migration, connection, {raise_on_warnings: true, throttler: throttler, printer: printer} ).run
      end

      assert_match "Unexpected warning found for inserted row: Duplicate entry '1001' for key '#{error_key}'", exception.message
    end

    it 'should copy and warn on unexpected warnings by default' do
      origin = table_create(:custom_primary_key)
      destination = table_create(:custom_primary_key_dest)
      migration = Lhm::Migration.new(origin, destination)

      execute("insert into custom_primary_key set id = 1001, pk = 1")
      execute("insert into custom_primary_key_dest set id = 1001, pk = 2")

      Lhm::Chunker.new(migration, connection, {throttler: throttler, printer: printer} ).run

      assert_equal 2, log_messages.length
      assert log_messages[1].include?("Unexpected warning found for inserted row: Duplicate entry '1001' for key '#{error_key}'"), log_messages
    end

    it 'should log two times for two unexpected warnings' do
      origin = table_create(:custom_primary_key)
      destination = table_create(:custom_primary_key_dest)
      migration = Lhm::Migration.new(origin, destination)

      execute("insert into custom_primary_key set id = 1001, pk = 1")
      execute("insert into custom_primary_key set id = 1002, pk = 2")
      execute("insert into custom_primary_key_dest set id = 1001, pk = 3")
      execute("insert into custom_primary_key_dest set id = 1002, pk = 4")

      Lhm::Chunker.new(migration, connection, {throttler: throttler, printer: printer} ).run

      assert_equal 3, log_messages.length
      assert log_messages[1].include?("Unexpected warning found for inserted row: Duplicate entry '1001' for key '#{error_key}'"), log_messages
      assert log_messages[2].include?("Unexpected warning found for inserted row: Duplicate entry '1002' for key '#{error_key}'"), log_messages
    end

    it 'should copy and warn on unexpected warnings' do
      origin = table_create(:custom_primary_key)
      destination = table_create(:custom_primary_key_dest)
      migration = Lhm::Migration.new(origin, destination)

      execute("insert into custom_primary_key set id = 1001, pk = 1")
      execute("insert into custom_primary_key_dest set id = 1001, pk = 2")

      Lhm::Chunker.new(migration, connection, {raise_on_warnings: false, throttler: throttler, printer: printer} ).run

      assert_equal 2, log_messages.length
      assert log_messages[1].include?("Unexpected warning found for inserted row: Duplicate entry '1001' for key '#{error_key}'"), log_messages
    end

    it 'should create the modified destination, even if the source is empty' do
      execute("truncate origin ")

      Lhm::Chunker.new(@migration, connection, {throttler: throttler, printer: printer} ).run

      replica do
        value(count_all(@destination.name)).must_equal(0)
      end

    end

    it 'should copy 23 rows from origin to destination in one shot, regardless of the value of the id' do
      23.times { |n| execute("insert into origin set id = '#{ n * n + 23 }'") }

      printer = mock("printer")
      printer.expects(:notify).with(kind_of(Integer), kind_of(Integer))
      printer.expects(:end)

      Lhm::Chunker.new(
        @migration, connection, { throttler: throttler, printer: printer }
      ).run

      replica do
        value(count_all(@destination.name)).must_equal(23)
      end
    end

    it 'should copy all the records of a table, even if the last chunk starts with the last record of it.' do
      11.times { |n| execute("insert into origin set id = '#{ n + 1 }'") }


      Lhm::Chunker.new(
        @migration, connection, { throttler: Lhm::Throttler::Time.new(stride: 10), printer: printer }
      ).run

      replica do
        value(count_all(@destination.name)).must_equal(11)
      end

    end

    it 'should copy 23 rows from origin to destination in one shot with replica lag based throttler, regardless of the value of the id' do
      23.times { |n| execute("insert into origin set id = '#{ 100000 + n * n + 23 }'") }

      printer = mock("printer")
      printer.expects(:notify).with(kind_of(Integer), kind_of(Integer))
      printer.expects(:end)

      Lhm::Throttler::Replica.any_instance.stubs(:replica_hosts).returns(['127.0.0.1'])
      Lhm::Throttler::ReplicaLag.any_instance.stubs(:master_replica_hosts).returns(['127.0.0.1'])

      Lhm::Chunker.new(
        @migration, connection, { throttler: Lhm::Throttler::ReplicaLag.new(stride: 100), printer: printer }
      ).run

      replica do
        value(count_all(@destination.name)).must_equal(23)
      end
    end

    it 'should throttle work stride based on replica lag' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()
      printer.expects(:notify).with(instance_of(Integer), instance_of(Integer)).twice
      printer.expects(:end)

      throttler = Lhm::Throttler::ReplicaLag.new(stride: 10, allowed_lag: 0)
      def throttler.max_current_replica_lag
        1
      end

      Lhm::Chunker.new(
        @migration, connection, { throttler: throttler, printer: printer }
      ).run

      assert_equal(Lhm::Throttler::ReplicaLag::INITIAL_TIMEOUT * 2 * 2, throttler.timeout_seconds)

      replica do
        value(count_all(@destination.name)).must_equal(15)
      end
    end

    it 'should detect a single replica with no lag in the default configuration' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()
      printer.expects(:notify).with(instance_of(Integer), instance_of(Integer)).twice
      printer.expects(:verify)
      printer.expects(:end)

      Lhm::Throttler::Replica.any_instance.stubs(:replica_hosts).returns(['127.0.0.1'])
      Lhm::Throttler::ReplicaLag.any_instance.stubs(:master_replica_hosts).returns(['127.0.0.1'])

      throttler = Lhm::Throttler::ReplicaLag.new(stride: 10, allowed_lag: 0)

      if master_replica_mode?
        def throttler.replica_connection(replica)
          config = ActiveRecord::Base.connection_pool.db_config.configuration_hash.dup
          config[:host] = replica
          config[:port] = 33007
          ActiveRecord::Base.send('mysql2_connection', config)
        end
      end

      Lhm::Chunker.new(
        @migration, connection, { throttler: throttler, printer: printer }
      ).run

      assert_equal(Lhm::Throttler::ReplicaLag::INITIAL_TIMEOUT, throttler.timeout_seconds)
      assert_equal(0, throttler.send(:max_current_replica_lag))

      replica do
        value(count_all(@destination.name)).must_equal(15)
      end

      printer.verify
    end

    it 'should abort early if the triggers are removed' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()

      failer = Proc.new { false }

      exception = assert_raises do
        Lhm::Chunker.new(
          @migration, connection, { verifier: failer, printer: printer, throttler: throttler }
        ).run
      end

      assert_match "Verification failed, aborting early", exception.message

      replica do
        value(count_all(@destination.name)).must_equal(0)
      end
    end
  end
end
