require 'lhm/timestamp'

module Lhm
  module Cleanup
    class Current
      def initialize(run, origin_table_name, connection)
        @run = run
        @origin_table_name = origin_table_name
        @connection = connection
        @ddls = []
      end

      attr_reader :run, :origin_table_name, :connection, :ddls

      def execute
        build_statements_for_drop_lhm_triggers_for_origin
        build_statements_for_rename_lhmn_tables_for_origin
        if run
          execute_ddls
        else
          report_ddls
        end
      end

      private

      def build_statements_for_drop_lhm_triggers_for_origin
        lhm_triggers_for_origin.each do |trigger|
          @ddls << "drop trigger if exists #{trigger}"
        end
      end

      def lhm_triggers_for_origin
        @lhm_triggers_for_origin ||= all_triggers_for_origin.select { |name| name =~ /^lhmt/ }
      end

      def all_triggers_for_origin
        @all_triggers_for_origin ||= connection.select_values("show triggers like '%#{origin_table_name}'").collect do |trigger|
          trigger.respond_to?(:trigger) ? trigger.trigger : trigger
        end
      end

      def build_statements_for_rename_lhmn_tables_for_origin
        lhmn_tables_for_origin.each do |table|
          @ddls << "rename table #{table} to #{failed_name}"
        end
      end

      def lhmn_tables_for_origin
        @lhmn_tables_for_origin ||= connection.select_values("show tables like 'lhmn_#{origin_table_name}'")
      end

      def failed_name
        # NOTE: MySQL table names are limited to 64 characters
        "lhma_#{Timestamp.new(Time.now)}_#{origin_table_name}_failed"[0..63]
      end

      def execute_ddls
        ddls.each do |ddl|
          connection.execute(ddl)
        end
      end

      def report_ddls
        puts "The following DDLs would be executed:"
        ddls.each { |ddl| puts ddl }
      end
    end
  end
end
