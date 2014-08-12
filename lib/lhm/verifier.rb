module Lhm
  class Verifier

    attr_reader :migrator, :connection

    def initialize(migrator, connection)
      @migrator = migrator
      @connections = connection
    end

    def risk
      puts "Table: #{@migrator.origin.name} with #{@migrator.statements.inspect}"
      puts @connection.select_one(%Q{SELECT table_name, (DATA_LENGTH+INDEX_LENGTH)/(1024*1024*1024) AS size FROM information_schema.tables WHERE table_name = '#{@migrator.origin.name}'})['size'].to_f
    end
  end
end
