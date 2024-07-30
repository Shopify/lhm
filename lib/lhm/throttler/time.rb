module Lhm
  module Throttler
    class Time
      include Command

      DEFAULT_TIMEOUT = 0.1
      DEFAULT_STRIDE = 2_000
      DEFAULT_BACKOFF_REDUCTION_FACTOR = 0.2 # 20%
      MIN_STRIDE_SIZE = 5

      attr_accessor :timeout_seconds
      attr_accessor :stride

      def initialize(options = {})
        @timeout_seconds = options[:delay] || DEFAULT_TIMEOUT
        @stride = options[:stride] || DEFAULT_STRIDE
        @backoff_reduction_factor = options[:backoff_reduction_factor] || DEFAULT_BACKOFF_REDUCTION_FACTOR
      end


      def backoff_stride
        new_stride = (@stride * (1 - @backoff_reduction_factor)).to_i

        if new_stride == @stride
          raise "Cannot backoff any further"
        end

        if new_stride < MIN_STRIDE_SIZE
          raise "Cannot reduce stride below #{MIN_STRIDE_SIZE}"
        end
        @stride = new_stride
      end

      def execute
        sleep timeout_seconds
      end
    end

    class LegacyTime < Time
      def initialize(timeout, stride)
        @timeout_seconds = timeout / 1000.0
        @stride = stride
      end
    end
  end
end
