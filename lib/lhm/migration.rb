# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/intersection'
require 'lhm/timestamp'

module Lhm
  class Migration
    attr_reader :origin, :destination, :conditions, :renames

    def initialize(origin, destination, conditions = nil, renames = {}, time = Time.now)
      @origin = origin
      @destination = destination
      @conditions = conditions
      @renames = renames
      @table_name = TableName.new(@origin.name, time)
    end

    def archive_name
      @archive_name ||= @table_name.archived
    end

    def intersection
      Intersection.new(@origin, @destination, @renames)
    end

    def origin_pk
      @origin_pk ||= origin.pk
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
