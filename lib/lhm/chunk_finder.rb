module Lhm
  class ChunkFinder
    def initialize(migration, connection = nil, options = {})
      @migration = migration
      @connection = connection
      @start = options[:start] || select_start_from_db
      @limit = options[:limit] || select_limit_from_db
    end

    attr_accessor :start, :limit

    def table_empty?
      start.nil? && limit.nil?
    end

    def validate
      if start > limit
        raise ArgumentError, "impossible chunk options (limit (#{limit.inspect} must be greater than start (#{start.inspect})"
      end
    end

    private

    def select_start_from_db
      @connection.select_value("select min(#{@migration.origin_pk}) from `#{ @migration.origin_name }`")
    end

    def select_limit_from_db
      @connection.select_value("select max(#{@migration.origin_pk}) from `#{ @migration.origin_name }`")
    end
  end
end
