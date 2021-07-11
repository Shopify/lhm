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

    class Percentage < Base
      def initialize
        super
        @max_length = 0
      end

      def notify(current_pk, max_pk, additional_info = {})
        return if !max_pk || max_pk == 0
        message = "%.2f%% (#{current_pk}/#{max_pk}) complete" % (current_pk.to_f / max_pk * 100.0)
        write(message)
      end

      def end
        write('100% complete')
        @output.write "\n"
      end

      def exception(e)
        write("failed: #{e}")
        @output.write "\n"
      end

      private

      def write(message)
        if (extra = @max_length - message.length) < 0
          @max_length = message.length
          extra = 0
        end

        @output.write "\r#{message}" + (' ' * extra)
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
