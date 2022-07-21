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

      def notify(current_pk, max_pk, additional_info = {})
        return if !max_pk || max_pk == 0

        # The argument current_pk represents the next_to_insert row id, and max_pk represents the
        # maximum id upto which chunker has to copy the data.
        # If all the rows are inserted upto max_pk, then current_pk passed here from chunker was
        # max_pk + 1, which leads to the printer printing the progress > 100%.
        return if current_pk >= max_pk

        message = "%.2f%% (#{current_pk}/#{max_pk}) complete" % (current_pk.to_f / max_pk * 100.0)
        write(message)
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
