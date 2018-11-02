# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

require 'lhm'

describe Lhm do
  include IntegrationHelper


    describe 'the simplest case' do
      before(:each) do
        connect_master!
        Lhm.cleanup(true)
        %w(fk_child_table origin_example).each do |table|
          execute "drop table if exists #{table}"
        end
        %w(origin_example fk_child_table).each do |table|
          execute "drop table if exists `fk_child_table`"
          table_create(table)
      end
    end

    after(:each) do
      Lhm.cleanup(true)
    end

    it 'should show the foreign key constraints for given table' do
      actual = table_read(:origin_example).references
      expected = [{
        "constraint_name"=> "fk_origin_table_id",
        "table_name"=> "fk_child_table",
        "table_schema"=> "test",
        "column_name"=> "origin_table_id",
        "referenced_column_name"=> "id"
      }]
      actual.must_equal(expected)
    end

    it 'migrates foreign key constraints for referencing tables' do
      Lhm.change_table(:origin_example) do |t|
        t.add_column(:new_column, "INT(12) DEFAULT '0'")
      end
      connect_master!

      actual = table_read(:origin_example).references
      expected = [{
        "constraint_name"=> "fk_origin_table_id",
        "table_name"=> "fk_child_table",
        "table_schema"=> "test",
        "column_name"=> "origin_table_id",
        "referenced_column_name"=> "id"
      }]
      actual.must_equal(expected)
    end
  end
end
