require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'lhm/migration'

describe Lhm::ChunkInsert do
  include IntegrationHelper

  describe 'insert_and_return_count_of_rows_created' do
    before(:each) do
      connect_master!
      @origin = table_create(:origin)
      @destination = table_create(:destination)
      @migration = Lhm::Migration.new(@origin, @destination)
      execute("insert into origin set id = 1001")
      @instance = Lhm::ChunkInsert.new(@migration, connection, 1001, 1001)
    end

    it "returns the count" do
      assert_equal 1, @instance.insert_and_return_count_of_rows_created
    end

    it "inserts the record into the slave" do
      @instance.insert_and_return_count_of_rows_created

      slave do
        count_all(@destination.name).must_equal(1)
      end
    end
  end
end
