module Lhm
  module Printer
    class Output
      def write(message)
        print message
      end
    end

    class Base
      def initialize
        @output = Output.new
      end
    end

    class Percentage
      def initialize
        @max_length = 0
      end

      def notify(lowest, highest)
        return if !highest || highest == 0

        # The argument lowest represents the next_to_insert row id, and highest represents the 
        # maximum id upto which chunker has to copy the data. 
        # If all the rows are inserted upto highest, then lowest passed here from chunker was 
        # highest + 1, which leads to the printer printing the progress > 100%.
        return if lowest >= highest
        
        message = "%.2f%% (#{lowest}/#{highest}) complete" % (lowest.to_f / highest * 100.0)
        write(message)
      end

      def notify_progress(progress)
      end

      def end
        write('100% complete')
      end

      def exception(e)
        Lhm.logger.error("failed: #{e}")
      end

      private

      def write(message)
        if (extra = @max_length - message.length) < 0
          @max_length = message.length
          extra = 0
        end

        Lhm.logger.info(message)
      end
    end

    class Dot < Base
      def notify(*)
        @output.write '.'
      end

      def end
        @output.write "\n"
      end
    end
  end
end
