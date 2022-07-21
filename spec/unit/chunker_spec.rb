# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'active_support/testing/time_helpers'

require 'lhm/table'
require 'lhm/migration'
require 'lhm/chunker'
require 'lhm/throttler'
require 'lhm/connection'

describe Lhm::Chunker do
  include ActiveSupport::Testing::TimeHelpers
  include UnitHelper

  EXPECTED_RETRY_FLAGS_CHUNKER = {:should_retry => true, :log_prefix => "Chunker"}
  EXPECTED_RETRY_FLAGS_CHUNK_INSERT = {:should_retry => true, :log_prefix => "ChunkInsert"}

  describe "Speedometer" do
    before(:each) do
      @window = 600
      @start_time = Time.now
      travel_to(@start_time)
      @speedometer = Lhm::Chunker::Speedometer.new(@window)
    end

    after(:each) do
      travel_back
    end

    describe "#speed" do
      it "should return nil if there is not enough data points" do
        @speedometer.speed.must_equal nil
      end

      it "should calculate difference for two points" do
        later = @start_time + 10
        travel_to(later)
        @speedometer << 10
        @speedometer.speed.must_equal 1.0
      end

      it "should keep one data point before the window" do
        times = [10, 20, 30, 40, 300, 610, 620]
        values = [431, 716, 1063, 1393, 10472, 21208, 21597]
        times.each_with_index do |t, i|
          travel_to(@start_time + times[i])
          @speedometer << values[i]
        end

        @speedometer.log.length.must_equal times.length - 1
        @speedometer.log[0][1].must_equal 716

        assert (@speedometer.speed - 34.7799).abs < 0.00001
      end
    end
  end

  before(:each) do
    @origin = Lhm::Table.new('foo')
    @destination = Lhm::Table.new('bar')
    @migration = Lhm::Migration.new(@origin, @destination)
    @connection = mock()
    @connection.stubs(:execute).returns([["dummy"]])
    # This is a poor man's stub
    @throttler = Object.new
    def @throttler.run
      # noop
    end
    def @throttler.stride
      1
    end

    @chunker = Lhm::Chunker.new(@migration, @connection, :throttler => @throttler,
                                                         :start     => 1,
                                                         :limit     => 10)
  end

  describe '#run' do

    it 'detects the max id to use in the chunk using the stride and use it if it is lower than the limit' do
      def @throttler.stride
        5
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 4/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(7)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 8 order by id limit 1 offset 4/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(21)
      @connection.expects(:update).with(regexp_matches(/between 1 and 7/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 8 and 10/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:execute).twice.with(regexp_matches(/show warnings/),EXPECTED_RETRY_FLAGS_CHUNKER).returns([])

      @chunker.run
    end


    it 'chunks the result set according to the stride size' do
      def @throttler.stride
        2
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(2)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 3 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(4)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 5 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(6)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 7 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(8)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 9 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(10)

      @connection.expects(:update).with(regexp_matches(/between 1 and 2/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 3 and 4/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 5 and 6/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 7 and 8/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 9 and 10/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)

      @chunker.run
    end

    it 'handles stride changes during execution' do
      # roll our own stubbing
      def @throttler.stride
        @run_count ||= 0
        @run_count = @run_count + 1
        if @run_count > 1
          3
        else
          2
        end
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(2)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 3 order by id limit 1 offset 2/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(5)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 6 order by id limit 1 offset 2/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(8)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 9 order by id limit 1 offset 2/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(nil)

      @connection.expects(:update).with(regexp_matches(/between 1 and 2/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 3 and 5/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 6 and 8/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 9 and 10/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)

      @connection.expects(:execute).twice.with(regexp_matches(/show warnings/),EXPECTED_RETRY_FLAGS_CHUNKER).returns([])

      @chunker.run
    end

    it 'correctly copies single record tables' do
      @chunker = Lhm::Chunker.new(@migration, @connection, :throttler => @throttler,
                                                           :start     => 1,
                                                           :limit     => 1)

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 0/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(nil)
      @connection.expects(:update).with(regexp_matches(/between 1 and 1/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(1)

      @chunker.run
    end

    it 'copies the last record of a table, even it is the start of the last chunk' do
      @chunker = Lhm::Chunker.new(@migration, @connection, :throttler => @throttler,
                                                           :start     => 2,
                                                           :limit     => 10)
      def @throttler.stride
        2
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 2 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(3)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 4 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(5)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 6 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(7)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 8 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(9)
      @connection.expects(:select_value).with(regexp_matches(/where id >= 10 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(nil)

      @connection.expects(:update).with(regexp_matches(/between 2 and 3/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 4 and 5/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 6 and 7/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 8 and 9/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(2)
      @connection.expects(:update).with(regexp_matches(/between 10 and 10/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(1)

      @chunker.run
    end


    it 'separates filter conditions from chunking conditions' do
      @chunker = Lhm::Chunker.new(@migration, @connection, :throttler => @throttler,
                                                           :start     => 1,
                                                           :limit     => 2)
      def @throttler.stride
        2
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(2)
      @connection.expects(:update).with(regexp_matches(/where \(foo.created_at > '2013-07-10' or foo.baz = 'quux'\) and `foo`/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(1)
      @connection.expects(:execute).with(regexp_matches(/show warnings/),EXPECTED_RETRY_FLAGS_CHUNKER).returns([])

      def @migration.conditions
        "where foo.created_at > '2013-07-10' or foo.baz = 'quux'"
      end

      @chunker.run
    end

    it "doesn't mess with inner join filters" do
      @chunker = Lhm::Chunker.new(@migration, @connection, :throttler => @throttler,
                                                           :start     => 1,
                                                           :limit     => 2)

      def @throttler.stride
        2
      end

      @connection.stubs(:select_rows).with(regexp_matches(/origin_table\.data_length \+ origin_table\.index_length/)).returns([[1024, 1048576]])
      @connection.expects(:select_value).with(regexp_matches(/where id >= 1 order by id limit 1 offset 1/),EXPECTED_RETRY_FLAGS_CHUNKER).returns(2)
      @connection.expects(:update).with(regexp_matches(/inner join bar on foo.id = bar.foo_id and/),EXPECTED_RETRY_FLAGS_CHUNK_INSERT).returns(1)
      @connection.expects(:execute).with(regexp_matches(/show warnings/),EXPECTED_RETRY_FLAGS_CHUNKER).returns([])

      def @migration.conditions
        'inner join bar on foo.id = bar.foo_id'
      end

      @chunker.run
    end
  end
end
