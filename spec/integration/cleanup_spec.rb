# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

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
        output = capture_stdout do
          Lhm.cleanup
        end
        output.must_include('Would drop LHM backup tables')
        output.must_match(/lhma_[0-9_]*_users/)
        output.must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary tables within range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do
          Lhm.cleanup false, { :until => Time.now - 86400 }
        end
        output.must_include('Would drop LHM backup tables')
        output.must_match(/lhma_[0-9_]*_users/)
        output.must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should exclude temporary tables outside range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do
          Lhm.cleanup false, { :until => Time.now - 172800 }
        end
        output.must_include('Would drop LHM backup tables')
        output.wont_match(/lhma_[0-9_]*_users/)
        output.wont_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary triggers' do
        output = capture_stdout do
          Lhm.cleanup
        end
        output.must_include('Would drop LHM triggers')
        output.must_include('lhmt_ins_users')
        output.must_include('lhmt_del_users')
        output.must_include('lhmt_upd_users')
        output.must_include('lhmt_ins_permissions')
        output.must_include('lhmt_del_permissions')
        output.must_include('lhmt_upd_permissions')
      end

      it 'should delete temporary tables' do
        Lhm.cleanup(true).must_equal(true)
        Lhm.cleanup.must_equal(true)
      end
    end

    describe 'cleanup_current_run' do
      it 'should show lhmn table for the specified table only' do
        table_create(:permissions)
        table_rename(:permissions, 'lhmn_permissions')
        output = capture_stdout do
          Lhm.cleanup_current_run(false, 'permissions')
        end.split("\n")

        assert_equal "The following DDLs would be executed:", output[0]
        assert_equal "drop trigger if exists lhmt_ins_permissions", output[1]
        assert_equal "drop trigger if exists lhmt_upd_permissions", output[2]
        assert_equal "drop trigger if exists lhmt_del_permissions", output[3]
        assert_match(/rename table lhmn_permissions to lhma_[0-9_]*_permissions_failed/, output[4])
        assert_equal 5, output.length
      end

      it 'should show temporary triggers for the specified table only' do
        output = capture_stdout do
          Lhm.cleanup_current_run(false, 'permissions')
        end.split("\n")
        assert_equal "The following DDLs would be executed:", output[0]
        assert_equal "drop trigger if exists lhmt_ins_permissions", output[1]
        assert_equal "drop trigger if exists lhmt_upd_permissions", output[2]
        assert_equal "drop trigger if exists lhmt_del_permissions", output[3]
        assert_equal 4, output.length
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

    describe 'failed_name' do
      before do
        @fake_time = Time.now
        Time.stubs(:now).returns(@fake_time)
      end

      after do
        Time.unstub(:now)
      end

      it 'should provide a table name with a maximum length of 64' do
        cleanup = Lhm::Cleanup::Current.new(nil, 'some_excessively_long_table_name_oh_dear_code_who_would_even_do_this_and_why', nil)
        assert_equal cleanup.instance_eval { failed_name }.size, 64
      end
    end
  end
end
