# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'lhm/table'
require 'lhm/migration'

describe Lhm::Chunker do
  include IntegrationHelper

  before(:each) { connect_master! }

  describe 'copying' do
    before(:each) do
      @origin = table_create(:origin)
      @destination = table_create(:destination)
      @migration = Lhm::Migration.new(@origin, @destination)
    end

    it 'should copy 1 row from origin to destination even if the id of the single row does not start at 1' do
      execute("insert into origin set id = 1001 ")
      printer = Lhm::Printer::Base.new

      def printer.notify(*) ;end
      def printer.end(*) [] ;end

      Lhm::Chunker.new(@migration, connection, {:throttler => Lhm::Throttler::Time.new(:stride => 100), :printer => printer} ).run

      slave do
        count_all(@destination.name).must_equal(1)
      end

    end

    it 'should create the modified destination, even if the source is empty' do
      execute("truncate origin ")
      printer = Lhm::Printer::Base.new

      def printer.notify(*) ;end
      def printer.end(*) [] ;end

      Lhm::Chunker.new(@migration, connection, {:throttler => Lhm::Throttler::Time.new(:stride => 100), :printer => printer} ).run

      slave do
        count_all(@destination.name).must_equal(0)
      end

    end

    it 'should copy 23 rows from origin to destination in one shot, regardless of the value of the id' do
      23.times { |n| execute("insert into origin set id = '#{ n * n + 23 }'") }

      printer = MiniTest::Mock.new
      printer.expect(:notify, :return_value, [Integer, Integer, Hash])
      printer.expect(:end, :return_value, [])

      Lhm::Chunker.new(
        @migration, connection, { :throttler => Lhm::Throttler::Time.new(:stride => 100), :printer => printer }
      ).run

      slave do
        count_all(@destination.name).must_equal(23)
      end

      printer.verify

    end

    it 'should copy all the records of a table, even if the last chunk starts with the last record of it.' do
      11.times { |n| execute("insert into origin set id = '#{ n + 1 }'") }

      printer = Lhm::Printer::Base.new

      def printer.notify(*) ;end
      def printer.end(*) [] ;end

      Lhm::Chunker.new(
        @migration, connection, { :throttler => Lhm::Throttler::Time.new(:stride => 10), :printer => printer }
      ).run

      slave do
        count_all(@destination.name).must_equal(11)
      end

    end

    it 'should copy 23 rows from origin to destination in one shot with slave lag based throttler, regardless of the value of the id' do
      23.times { |n| execute("insert into origin set id = '#{ 100000 + n * n + 23 }'") }

      printer = MiniTest::Mock.new
      printer.expect(:notify, :return_value, [Integer, Integer, Hash])
      printer.expect(:end, :return_value, [])

      Lhm::Chunker.new(
        @migration, connection, { :throttler => Lhm::Throttler::SlaveLag.new(:stride => 100), :printer => printer }
      ).run

      slave do
        count_all(@destination.name).must_equal(23)
      end

      printer.verify
    end

    it 'should throttle work stride based on slave lag' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()
      printer.expects(:notify).with(instance_of(Integer), instance_of(Integer), instance_of(Hash)).twice
      printer.expects(:end)

      throttler = Lhm::Throttler::SlaveLag.new(:stride => 10, :allowed_lag => 0)
      def throttler.max_current_slave_lag
        1
      end

      Lhm::Chunker.new(
        @migration, connection, { :throttler => throttler, :printer => printer }
      ).run

      assert_equal(Lhm::Throttler::SlaveLag::INITIAL_TIMEOUT * 2 * 2, throttler.timeout_seconds)

      slave do
        count_all(@destination.name).must_equal(15)
      end
    end

    it 'should detect a single slave with no lag in the default configuration' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()
      printer.expects(:notify).with(instance_of(Integer), instance_of(Integer), instance_of(Hash)).twice
      printer.expects(:verify)
      printer.expects(:end)

      throttler = Lhm::Throttler::SlaveLag.new(:stride => 10, :allowed_lag => 0)

      def throttler.slave_hosts
        ['127.0.0.1']
      end

      if master_slave_mode?
        def throttler.slave_connection(slave)
          config = ActiveRecord::Base.connection_pool.spec.config.dup
          config[:host] = slave
          config[:port] = 3307
          ActiveRecord::Base.send('mysql2_connection', config)
        end
      end

      Lhm::Chunker.new(
        @migration, connection, { :throttler => throttler, :printer => printer }
      ).run

      assert_equal(Lhm::Throttler::SlaveLag::INITIAL_TIMEOUT, throttler.timeout_seconds)
      assert_equal(0, throttler.send(:max_current_slave_lag))

      slave do
        count_all(@destination.name).must_equal(15)
      end

      printer.verify
    end

    it 'should abort early if the triggers are removed' do
      15.times { |n| execute("insert into origin set id = '#{ (n * n) + 1 }'") }

      printer = mock()

      failer = Proc.new { false }

      exception = assert_raises do
        Lhm::Chunker.new(
          @migration, connection, { :verifier => failer, :printer => printer, :throttler => Lhm::Throttler::Time.new(:stride => 100) }
        ).run
      end

      assert_match "Verification failed, aborting early", exception.message

      slave do
        count_all(@destination.name).must_equal(0)
      end
    end
  end
end
