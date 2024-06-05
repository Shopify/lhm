# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/intersection'
require 'lhm/timestamp'

module Lhm
  class Migration
    attr_reader :origin, :destination, :conditions, :renames

    def initialize(origin, destination, conditions = nil, renames = {}, time = Time.now, generated_column_names = [])
      @origin = origin
      @destination = destination
      @conditions = conditions
      @renames = renames
      @table_name = TableName.new(@origin.name, time)
      @generated_column_names = generated_column_names
    end

    def archive_name
      @archive_name ||= @table_name.archived
    end

    def intersection
      Intersection.new(@origin, @destination, @renames, @generated_column_names)
    end

    def origin_name
      @table_name.original
    end

    def origin_columns
      @origin_columns ||= intersection.origin.typed(origin_name)
    end

    def destination_name
      @destination_name ||= destination.name
    end

    def destination_columns
      @destination_columns ||= intersection.destination.joined
    end
  end
end
