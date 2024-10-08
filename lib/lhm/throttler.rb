require 'lhm/throttler/backoff_reduction'
require 'lhm/throttler/time'
require 'lhm/throttler/replica_lag'
require 'lhm/throttler/slave_lag'
require 'lhm/throttler/threads_running'

module Lhm
  module Throttler
    CLASSES = {
      :time_throttler => Throttler::Time,
      :replica_lag_throttler => Throttler::ReplicaLag,
      :slave_lag_throttler => Throttler::SlaveLag,
      :threads_running_throttler => Throttler::ThreadsRunning
    }

    def throttler
      @throttler ||= Throttler::Time.new
    end

    def setup_throttler(type, options = {})
      @throttler = Factory.create_throttler(type, options)
    end

    class Factory
      def self.create_throttler(type, options = {})
        case type
        when Lhm::Command
          type
        when Symbol
          CLASSES[type].new(options)
        when String
          CLASSES[type.to_sym].new(options)
        when Class
          type.new(options)
        else
          raise ArgumentError, 'type argument must be a Symbol, String or Class'
        end
      end
    end
  end
end
