# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'lhm/command'
require 'lhm/sql_helper'
require 'lhm/printer'
require 'lhm/chunk_insert'
require 'lhm/chunk_finder'

module Lhm
  class Chunker
    include Command
    include SqlHelper

    attr_reader :connection

    # Copy from origin to destination in chunks of size `stride`.
    # Use the `throttler` class to sleep between each stride.
    def initialize(migration, connection = nil, options = {})
      @migration = migration
      @connection = connection
      @chunk_finder = ChunkFinder.new(migration, connection, options)
      if @throttler = options[:throttler]
        @throttler.connection = @connection if @throttler.respond_to?(:connection=)
      end
      @start = @chunk_finder.start
      @limit = @chunk_finder.limit
      @printer = options[:printer] || Printer::Percentage.new
    end

    def execute
      return if @chunk_finder.table_empty?
      @next_to_insert = @start
      while @next_to_insert <= @limit || (@start == @limit)
        stride = @throttler.stride
        top = upper_id(@next_to_insert, stride)
        affected_rows = ChunkInsert.new(@migration, @connection, bottom, top).insert_and_return_count_of_rows_created
        if @throttler && affected_rows > 0
          @throttler.run
        end
        @printer.notify(bottom, @limit)
        @next_to_insert = top + 1
        break if @start == @limit
      end
      @printer.end
    end

    private

    def bottom
      @next_to_insert
    end

    def upper_id(next_id, stride)
      pk = @migration.origin_pk

      top = connection.select_value("select #{ pk } from `#{ @migration.origin_name }` where #{ pk } >= #{ next_id } order by #{ pk } limit 1 offset #{ stride - 1}")
      [top ? top.to_i : @limit, @limit].min
    end

    def validate
      return if @chunk_finder.table_empty?
      @chunk_finder.validate
    end
  end
end
