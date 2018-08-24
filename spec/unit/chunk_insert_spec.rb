# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/chunk_insert'

describe Lhm::ChunkInsert do
  before(:each) do
    @connection = stub(:connection)
    @origin = Lhm::Table.new('foo')
    @destination = Lhm::Table.new('bar')
  end

  describe "#sql" do
    describe "when migration has no conditions" do
      before { @migration = Lhm::Migration.new(@origin, @destination) }

      it "uses a simple where clause" do
        assert_equal(
          Lhm::ChunkInsert.new(@migration, @connection, 1, 2).sql,
          "insert ignore into `bar` () select  from `foo` where `foo`.`id` between 1 and 2"
        )
      end
    end

    describe "when migration has a WHERE condition" do
      before do
        @migration = Lhm::Migration.new(
          @origin,
          @destination,
          "where foo.created_at > '2013-07-10' or foo.baz = 'quux'"
        )
      end

      it "combines the clause with the chunking WHERE condition" do
        assert_equal(
          Lhm::ChunkInsert.new(@migration, @connection, 1, 2).sql,
          "insert ignore into `bar` () select  from `foo` where (foo.created_at > '2013-07-10' or foo.baz = 'quux') and `foo`.`id` between 1 and 2"
        )
      end
    end

    describe "when primary key is not id" do
      before do
        @origin = Lhm::Table.new('foo', 'foo_id')
        @destination = Lhm::Table.new('bar', 'foo_id')
        @migration = Lhm::Migration.new(@origin, @destination)
      end

      it "works with primary key not called id" do
        assert_equal(
          Lhm::ChunkInsert.new(@migration, @connection, 1, 2).sql,
          "insert ignore into `bar` () select  from `foo` where `foo`.`foo_id` between 1 and 2"
        )
      end
    end
  end
end
