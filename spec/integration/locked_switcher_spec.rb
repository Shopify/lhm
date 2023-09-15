# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

require 'lhm/table'
require 'lhm/migration'
require 'lhm/locked_switcher'

describe Lhm::LockedSwitcher do
  include IntegrationHelper

  before(:each) do
    connect_master!
    @old_logger = Lhm.logger
    Lhm.logger = Logger.new('/dev/null')
  end

  after(:each) do
    Lhm.logger = @old_logger
  end

  describe 'switching' do
    before(:each) do
      @origin = table_create('origin')
      @destination = table_create('destination')
      @migration = Lhm::Migration.new(@origin, @destination)
      Lhm.progress = Lhm::Progress.new(@origin, connection)
    end

    it 'rename origin to archive' do
      switcher = Lhm::LockedSwitcher.new(@migration, connection)
      switcher.run

      replica do
        value(data_source_exists?(@origin)).must_equal true
        value(table_read(@migration.archive_name).columns.keys).must_include 'origin'
      end
    end

    it 'rename destination to origin' do
      switcher = Lhm::LockedSwitcher.new(@migration, connection)
      switcher.run

      replica do
        value(data_source_exists?(@destination)).must_equal false
        value(table_read(@origin.name).columns.keys).must_include 'destination'
      end
    end
  end
end
