require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/printer'
require 'logger'



describe Lhm::Printer do
  include UnitHelper

  describe 'percentage printer' do

    before(:each) do
      @printer = Lhm::Printer::Percentage.new
    end

    it 'prints the percentage' do
      r, w = IO.pipe
      Lhm.logger = Logger.new(w)

      10.times do |i|
        @printer.notify(i, 10)
        assert_match(/#{i}\/10/, log_expression_message(r.gets))
      end
    end

    it 'always prints a bigger message' do
      @length = 0

      def assert_length(printer)
        new_length = printer.instance_variable_get(:@max_length)
        assert new_length >= @length
        @length = new_length
      end

      @printer.notify(10, 100)
      assert_length(@printer)
      @printer.notify(0, 100)
      assert_length(@printer)
      @printer.notify(1, 1000000)
      assert_length(@printer)
      @printer.notify(0, 0)
      assert_length(@printer)
      @printer.notify(0, nil)
      assert_length(@printer)
    end

    it 'prints the end message' do
      r, w = IO.pipe
      Lhm.logger = Logger.new(w)
      @printer.end

      assert_equal(log_expression_message(r.gets), "100% complete\n")
    end

    it 'prints the exception message' do
      r, w = IO.pipe
      Lhm.logger = Logger.new(w)
      e = StandardError.new('woops')
      @printer.exception(e)

      assert_equal(log_expression_message(r.gets), "failed: #{e}\n")
    end
  end

  describe 'dot printer' do

    before(:each) do
      @printer = Lhm::Printer::Dot.new
    end

    it 'prints the dots' do
      mock  = mock("output")
      mock.expects(:write).with('.').times(10)

      @printer.instance_variable_set(:@output, mock)
      10.times { @printer.notify }
    end

  end
end
