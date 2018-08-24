require 'lhm/sql_retry'

module Lhm
  class ChunkInsert
    def initialize(migration, connection, lowest, highest, options = {})
      @migration = migration
      @connection = connection
      @lowest = lowest
      @highest = highest
      @retry_helper = SqlRetry.new(
        @connection,
        {
          log_prefix: "Chunker Insert"
        }.merge!(options.fetch(:retriable, {}))
      )
    end

    def insert_and_return_count_of_rows_created
      @retry_helper.with_retries do |retriable_connection|
        retriable_connection.update sql
      end
    end

    def sql
      "insert ignore into `#{ @migration.destination_name }` (#{ @migration.destination_columns }) " \
      "select #{ @migration.origin_columns } from `#{ @migration.origin_name }` " \
      "#{ conditions } `#{ @migration.origin_name }`.`#{@migration.origin_pk}` between #{ @lowest } and #{ @highest }"
    end

    private
    # XXX this is extremely brittle and doesn't work when filter contains more
    # than one SQL clause, e.g. "where ... group by foo". Before making any
    # more changes here, please consider either:
    #
    # 1. Letting users only specify part of defined clauses (i.e. don't allow
    # `filter` on Migrator to accept both WHERE and INNER JOIN
    # 2. Changing query building so that it uses structured data rather than
    # strings until the last possible moment.
    def conditions
      if @migration.conditions
        @migration.conditions.
          # strip ending paren
          sub(/\)\Z/, '').
          # put any where conditions in parens
          sub(/where\s(\w.*)\Z/, 'where (\\1)') + ' and'
      else
        'where'
      end
    end
  end
end
