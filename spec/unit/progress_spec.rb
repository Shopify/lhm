require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/progress'
require 'test_helper'
require 'active_support/testing/time_helpers'

describe Lhm::Progress do
  include ActiveSupport::Testing::TimeHelpers
  include UnitHelper

  describe 'Speedometer' do
    before(:each) do
      @window = 600
      @start_time = Time.now
      travel_to(@start_time)
      @speedometer = Lhm::Progress::Speedometer.new(@window)
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

        assert_equal @speedometer.speed, 34.78
      end
    end

    describe "Progress" do
      before(:each) do
        @options = {:verbose_logging => true}
      end

      describe '#update_during_copy' do
        it 'outputs copy progress correctly' do
          connection = mock()
          connection.stubs(:current_database).returns('foo')
          connection.stubs(:select_rows).returns([[20, 80000]])

          printer = mock()
          options = {
            :verbose_logging => true,
            :printer => printer
          }
          @options[:printer] = printer
          expected_progress = progress
          expected_progress["state"] = Lhm::STATE_COPYING
          expected_progress["completion_percentage"] = "#{(2000 / 4000.to_f) * 100}% complete"
          expected_progress["estimated_bytes_copied"] = (2000 * 20)
          expected_progress["rows_written"] = 2000
          expected_progress["estimated_copy_speed"] = " bytes/sec"
          printer.expects(:notify_progress).with(progress).returns()
          printer.expects(:notify_progress).with(expected_progress).returns()
          
          progress = Lhm::Progress.new(Lhm::Table.new('foo'), connection, options: options)
          progress.update_before_copy(1, 4000)
          progress.update_state(Lhm::STATE_COPYING)
          progress.update_during_copy(2000)
        end
      end

      describe '#update_state' do
        it 'updates the state correctly' do
          connection = mock()
          connection.stubs(:current_database).returns('foo')
          connection.stubs(:select_rows).returns([[20, 80000]])

          printer = mock()
          options = {
            :verbose_logging => true,
            :printer => printer
          }

          expected_progress = progress
          expected_progress["state"] = Lhm::STATE_COPYING_DONE
          expected_progress["completion_percentage"] = "100% complete"

          printer.expects(:notify_progress).with(progress).returns()
          printer.expects(:notify_progress).with(expected_progress).returns()
           
          progress = Lhm::Progress.new(Lhm::Table.new('foo'), connection, options: options)
          assert_equal progress.state, Lhm::STATE_INITIAL
          progress.update_before_copy(1, 4000)
          progress.update_state(Lhm::STATE_COPYING)
          progress.update_state(Lhm::STATE_COPYING_DONE)
        end
      end
    end
  end
end
