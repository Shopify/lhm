# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'ostruct'

describe Lhm, 'cleanup' do
  include IntegrationHelper
  before(:each) { connect_master! }

  describe 'changes' do
    before(:each) do
      table_create(:users)
      table_create(:permissions)
      simulate_failed_migration do
        Lhm.change_table(:users, :atomic_switch => false) do |t|
          t.add_column(:logins, "INT(12) DEFAULT '0'")
          t.add_index(:logins)
        end
      end
      simulate_failed_migration do
        Lhm.change_table(:permissions, :atomic_switch => false) do |t|
          t.add_column(:user_id, "INT(12) DEFAULT '0'")
          t.add_index(:user_id)
        end
      end
    end

    after(:each) do
      Lhm.cleanup(true)
    end

    describe 'cleanup' do
      it 'should show temporary tables' do
        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup
        end
        value(output).must_include('Would drop LHM backup tables')
        value(output).must_match(/lhma_[0-9_]*_users/)
        value(output).must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary tables within range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup false, { :until => Time.now - 86400 }
        end
        value(output).must_include('Would drop LHM backup tables')
        value(output).must_match(/lhma_[0-9_]*_users/)
        value(output).must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should exclude temporary tables outside range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup false, { :until => Time.now - 172800 }
        end
        value(output).must_include('Would drop LHM backup tables')
        value(output).wont_match(/lhma_[0-9_]*_users/)
        value(output).wont_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary triggers' do
        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup
        end
        value(output).must_include('Would drop LHM triggers')
        value(output).must_include('lhmt_ins_users')
        value(output).must_include('lhmt_del_users')
        value(output).must_include('lhmt_upd_users')
        value(output).must_include('lhmt_ins_permissions')
        value(output).must_include('lhmt_del_permissions')
        value(output).must_include('lhmt_upd_permissions')
      end

      it 'should delete temporary tables' do
        value(Lhm.cleanup(true)).must_equal(true)
        value(Lhm.cleanup).must_equal(true)
      end

      it 'outputs deleted tables and triggers' do
        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup(true)
        end
        value(output).must_include('Dropped triggers lhmt_ins_users, lhmt_upd_users, lhmt_del_users, lhmt_ins_permissions, lhmt_upd_permissions, lhmt_del_permissions')
      end
    end

    describe 'cleanup_current_run' do
      it 'should show lhmn table for the specified table only' do
        table_create(:permissions)
        table_rename(:permissions, 'lhmn_permissions')
        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup_current_run(false, 'permissions')
        end

        value(output).must_include("The following DDLs would be executed:")
        value(output).must_include("drop trigger if exists `lhmt_ins_permissions`")
        value(output).must_include("drop trigger if exists `lhmt_upd_permissions`")
        value(output).must_include("drop trigger if exists `lhmt_del_permissions`")
      end

      it 'should show temporary triggers for the specified table only' do
        output = capture_stdout do |logger|
          Lhm.logger = logger
          Lhm.cleanup_current_run(false, 'permissions')
        end
        value(output).must_include("The following DDLs would be executed:")
        value(output).must_include("drop trigger if exists `lhmt_ins_permissions`")
        value(output).must_include("drop trigger if exists `lhmt_upd_permissions`")
        value(output).must_include("drop trigger if exists `lhmt_del_permissions`")
      end

      it 'should delete temporary tables and triggers for the specified table only' do
        assert Lhm.cleanup_current_run(true, 'permissions')

        all_tables = Lhm.connection.select_values('show tables')
        all_triggers = Lhm.connection.select_values('show triggers')

        refute all_tables.include?('lhmn_permissions')
        assert all_tables.find { |t| t =~ /lhma_(.*)_users/}

        refute all_triggers.find { |t| t =~ /lhmt_(.*)_permissions/}
        assert all_triggers.find { |t| t =~ /lhmt_(.*)_users/}
      end
    end
  end

  describe 'names that need quoting' do
    before(:each) do
      table_create(:users)
      table_create(:permissions)
    end

    def all_tables
      Lhm.connection.select_values('show tables')
    end

    def all_triggers
      Lhm.connection.select_values('show triggers')
    end

    it 'drops a leftover table with a comma in its name and no other table' do
      execute('create table `lhmn_leftover,users` (id int)')

      assert Lhm.cleanup(true)

      assert all_tables.include?('users')
      refute all_tables.include?('lhmn_leftover,users')
    end

    it 'drops leftover tables whose names hold spaces, dots and backticks' do
      execute('create table `lhmn_with space` (id int)')
      execute('create table `lhma_with.dot` (id int)')
      execute('create table `lhmn_with``tick` (id int)')

      assert Lhm.cleanup(true)

      value(all_tables.grep(/^lhm/)).must_equal([])
      assert all_tables.include?('users')
      assert all_tables.include?('permissions')
    end

    it 'drops a leftover trigger whose name needs quoting' do
      execute('create trigger `lhmt_with space` after insert on users for each row set @lhm_spec = 1')

      assert Lhm.cleanup(true)

      refute all_triggers.include?('lhmt_with space')
      assert all_tables.include?('users')
    end

    it 'quotes trigger and table names when it cleans up the current run' do
      table_rename(:permissions, 'lhmn_permissions')
      table_create(:permissions)
      execute('create trigger `lhmt_with space_permissions` after insert on permissions for each row set @lhm_spec = 1')

      output = capture_stdout do |logger|
        Lhm.logger = logger
        Lhm.cleanup_current_run(false, 'permissions')
      end
      value(output).must_include('drop trigger if exists `lhmt_with space_permissions`')
      value(output).must_include('rename table `lhmn_permissions` to `lhma_')

      assert Lhm.cleanup_current_run(true, 'permissions')

      refute all_triggers.include?('lhmt_with space_permissions')
      refute all_tables.include?('lhmn_permissions')
      assert all_tables.include?('permissions')
    end
  end
end
