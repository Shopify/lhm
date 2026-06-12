require 'minitest/autorun'
require 'minitest/spec'
require 'active_record'
require 'lhm/sql_retry'
require 'trilogy'

describe Lhm::SqlRetry do
  describe '#default_retry_config' do
    it 'uses an effectively unbounded max elapsed time value compatible with retriable validation' do
      retry_config = Lhm::SqlRetry.new(nil).send(:default_retry_config)

      assert_equal Float::MAX, retry_config[:max_elapsed_time]
    end
  end

  describe '#retriable_trilogy_errors' do
    it 'only uses exception classes as retriable keys' do
      retry_errors = Lhm::SqlRetry.new(nil).send(:retriable_trilogy_errors)

      retry_errors.each_key do |error_class|
        assert error_class.is_a?(Class), "#{error_class.inspect} is not a class"
        assert error_class <= Exception, "#{error_class.inspect} is not an exception class"
      end
    end

    it 'matches trilogy connection error classes without using the ConnectionError module' do
      retry_errors = Lhm::SqlRetry.new(nil).send(:retriable_trilogy_errors)

      refute_includes retry_errors.keys, Trilogy::ConnectionError
      assert_includes retry_errors.keys, Trilogy::BaseConnectionError
      assert_includes retry_errors.keys, Trilogy::ConnectionClosed
      assert_includes retry_errors.keys, Trilogy::SSLError
    end
  end
end
