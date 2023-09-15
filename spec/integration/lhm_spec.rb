# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'integration/toxiproxy_helper'

describe Lhm do
  include IntegrationHelper

  before(:each) { connect_master!; Lhm.cleanup(true) }

  describe 'id column requirement' do
    it 'should migrate the table when id is pk' do
      table_create(:users)

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_column(:logins, "int(12) default '0'")
      end

      replica do
        value(table_read(:users).columns['logins']).must_equal({
          :type           => 'int(12)',
          :is_nullable    => 'YES',
          :column_default => '0',
          :comment => '',
          :collate => nil,
        })
      end
    end

    it 'should migrate the table when id is not pk' do
      table_create(:custom_primary_key)

      Lhm.change_table(:custom_primary_key, {:atomic_switch => false}) do |t|
        t.add_column(:logins, "int(12) default '0'")
      end

      replica do
        value(table_read(:custom_primary_key).columns['logins']).must_equal({
          :type           => 'int(12)',
          :is_nullable    => 'YES',
          :column_default => '0',
          :comment => '',
          :collate => nil,
        })
      end
    end

    it 'should migrate the table when using a composite primary key if id column exists' do
      table_create(:composite_primary_key)

      Lhm.change_table(:composite_primary_key, {:atomic_switch => false}) do |t|
        t.add_column(:logins, "int(12) default '0'")
      end

      replica do
        value(table_read(:composite_primary_key).columns['logins']).must_equal({
          :type           => 'int(12)',
          :is_nullable    => 'YES',
          :column_default => '0',
          :comment => '',
          :collate => nil,
        })
      end
    end
  end

  describe 'changes' do
    before(:each) do
      table_create(:users)
      table_create(:tracks)
      table_create(:permissions)
    end

    describe 'when changing to a composite primary key' do
      it 'should be able to use ddl statement to create composite keys' do

        Lhm.change_table(:users, {:atomic_switch => false}) do |t|
          t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL")
          t.ddl("ALTER TABLE #{t.name} DROP PRIMARY KEY, ADD PRIMARY KEY (username, id)")
          t.ddl("ALTER TABLE #{t.name} ADD INDEX (id)")
          t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL AUTO_INCREMENT")
        end

        replica do
          value(connection.primary_key('users')).must_equal(['username', 'id'])
        end
      end

    end

    describe 'when providing a subset of data to copy' do

      before do
        execute('insert into tracks set id = 13, public = 0')
        11.times { |n| execute("insert into tracks set id = #{n + 1}, public = 1") }
        11.times { |n| execute("insert into permissions set track_id = #{n + 1}") }

        Lhm.change_table(:permissions, {:atomic_switch => false}) do |t|
          t.filter('inner join tracks on tracks.`id` = permissions.`track_id` and tracks.`public` = 1')
        end
      end

      describe 'when no additional data is inserted into the table' do

        it 'migrates the existing data' do
          replica do
            value(count_all(:permissions)).must_equal(11)
          end
        end
      end

      describe 'when additional data is inserted' do

        before do
          execute('insert into tracks set id = 14, public = 0')
          execute('insert into tracks set id = 15, public = 1')
          execute('insert into permissions set track_id = 14')
          execute('insert into permissions set track_id = 15')
        end

        it 'migrates all data' do
          replica do
            value(count_all(:permissions)).must_equal(13)
          end
        end
      end
    end

    it 'should add a column' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_column(:logins, "INT(12) DEFAULT '0'")
      end

      replica do
        value(table_read(:users).columns['logins']).must_equal({
          :type => 'int(12)',
          :is_nullable => 'YES',
          :column_default => '0',
          :comment => '',
          :collate => nil,
        })
      end
    end

    it 'should copy all rows' do
      23.times { |n| execute("insert into users set reference = '#{ n }'") }

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_column(:logins, "INT(12) DEFAULT '0'")
      end

      replica do
        value(count_all(:users)).must_equal(23)
      end
    end

    it 'should remove a column' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.remove_column(:comment)
      end

      replica do
        assert_nil table_read(:users).columns['comment']
      end
    end

    it 'should add an index' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_index([:comment, :created_at])
      end

      replica do
        value(index_on_columns?(:users, [:comment, :created_at])).must_equal(true)
      end
    end

    it 'should add an index with a custom name' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_index([:comment, :created_at], :my_index_name)
      end

      replica do
        value(index?(:users, :my_index_name)).must_equal(true)
      end
    end

    it 'should add an index on a column with a reserved name' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_index(:group)
      end

      replica do
        value(index_on_columns?(:users, :group)).must_equal(true)
      end
    end

    it 'should add a unique index' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.add_unique_index(:comment)
      end

      replica do
        value(index_on_columns?(:users, :comment, :unique)).must_equal(true)
      end
    end

    it 'should remove an index' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.remove_index([:username, :created_at])
      end

      replica do
        value(index_on_columns?(:users, [:username, :created_at])).must_equal(false)
      end
    end

    it 'should remove an index with a custom name' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.remove_index([:username, :group])
      end

      replica do
        value(index?(:users, :index_with_a_custom_name)).must_equal(false)
      end
    end

    it 'should remove an index with a custom name by name' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.remove_index(:irrelevant_column_name, :index_with_a_custom_name)
      end

      replica do
        value(index?(:users, :index_with_a_custom_name)).must_equal(false)
      end
    end

    it 'should add an index with column sizes' do
      Lhm.change_table(:users, :atomic_switch => false) do |t|
        t.add_index(["username(6)", "group (10)", "comment     (10)"])
      end

      replica do
        value(index_on_columns?(:users, [:username, :group, :comment])).must_equal(true)
      end
    end

    it 'should apply a ddl statement' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.ddl('alter table %s add column flag tinyint(1)' % t.name)
      end

      replica do
        value(table_read(:users).columns['flag']).must_equal({
          :type => 'tinyint(1)',
          :is_nullable => 'YES',
          :column_default => nil,
          :comment => '',
          :collate => nil,
        })
      end
    end

    it 'should change a column' do
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.change_column(:comment, "varchar(20) DEFAULT 'none' NOT NULL")
      end

      replica do
        value(table_read(:users).columns['comment']).must_equal({
          :type => 'varchar(20)',
          :is_nullable => 'NO',
          :column_default => 'none',
          :comment => '',
          :collate => 'utf8_general_ci',
        })
      end
    end

    it 'should change the last column in a table' do
      table_create(:small_table)

      Lhm.change_table(:small_table, {:atomic_switch => false}) do |t|
        t.change_column(:id, 'int(5)')
      end

      replica do
        value(table_read(:small_table).columns['id']).must_equal({
          :type => 'int(5)',
          :is_nullable => 'NO',
          :column_default => nil,
          :comment => '',
          :collate => nil,
        })
      end
    end

    it 'should rename a column' do
      table_create(:users)

      execute("INSERT INTO users (username) VALUES ('a user')")
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:username, :login)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['username']
        value(table_read(:users).columns['login']).must_equal({
          :type => 'varchar(255)',
          :is_nullable => 'YES',
          :column_default => nil,
          :comment => '',
          :collate => 'utf8_general_ci',
        })

        result = select_one('SELECT login from users')
        result = result['login'] if result.respond_to?(:has_key?)
        value(result).must_equal('a user')
      end
    end

    it 'should rename a column with a default' do
      table_create(:users)

      execute("INSERT INTO users (username) VALUES ('a user')")
      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:group, :fnord)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['group']
        value(table_read(:users).columns['fnord']).must_equal({
          :type => 'varchar(255)',
          :is_nullable => 'YES',
          :column_default => 'Superfriends',
          :comment => '',
          :collate => 'utf8_general_ci',
        })

        result = select_one('SELECT `fnord` from users')
        result = result['fnord'] if result.respond_to?(:has_key?)
        value(result).must_equal('Superfriends')
      end
    end

    it 'should rename a column with a collate' do
      table_create(:users)

      execute("ALTER TABLE users MODIFY `username` varchar(255) COLLATE utf8mb4_unicode_ci NULL")
      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:username, :user_name)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['username']
        value(table_read(:users).columns['user_name']).must_equal({
             :type => 'varchar(255)',
             :is_nullable => 'YES',
             :column_default => nil,
             :comment => '',
             :collate => 'utf8mb4_unicode_ci',
           })

        result = select_one('SELECT `user_name` from users')
        result = result['user_name'] if result.respond_to?(:has_key?)
        value(result).must_equal('a user')
      end
    end


    it 'should rename a column with a comment' do
      table_create(:users)

      execute("ALTER TABLE users MODIFY `reference` int(11) DEFAULT NULL COMMENT 'RefComment'")
      execute("INSERT INTO users (username,reference) VALUES ('a user', 10)")

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:reference, :ref)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['reference']
        value(table_read(:users).columns['ref']).must_equal({
           :type => 'int(11)',
           :is_nullable => 'YES',
           :column_default => nil,
           :comment => 'RefComment',
           :collate => nil,
         })

        result = select_one('SELECT `ref` from users')
        result = result['ref'] if result.respond_to?(:has_key?)
        value(result).must_equal(10)
      end
    end

    it 'should rename a column with a default null' do
      table_create(:users)

      execute("ALTER TABLE users MODIFY `group` varchar(255) NULL DEFAULT NULL")
      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:group, :fnord)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['group']
        value(table_read(:users).columns['fnord']).must_equal({
           :type => 'varchar(255)',
           :is_nullable => 'YES',
           :column_default => nil,
           :comment => '',
           :collate => 'utf8_general_ci',
         })

        result = select_one('SELECT `fnord` from users')
        result = result['fnord'] if result.respond_to?(:has_key?)
        assert_nil(result)
      end
    end

    it 'should rename a colmn with nullable' do
      table_create(:users)
      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:username, :user_name)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['username']
        value(table_read(:users).columns['user_name']).must_equal({
          :type => 'varchar(255)',
          :is_nullable => 'YES',
          :column_default => nil,
          :comment => '',
          :collate => 'utf8_general_ci',
        })

        result = select_one('SELECT `user_name` from users')
        result = result['user_name'] if result.respond_to?(:has_key?)
        value(result).must_equal('a user')
      end
    end

    it 'should rename a column with a not null' do
      table_create(:users)

      execute("ALTER TABLE users MODIFY username varchar(255) NOT NULL")
      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm.change_table(:users, {:atomic_switch => false}) do |t|
        t.rename_column(:username, :user_name)
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['username']
        value(table_read(:users).columns['user_name']).must_equal({
          :type => 'varchar(255)',
          :is_nullable => 'NO',
          :column_default => nil,
          :comment => '',
          :collate => 'utf8_general_ci',
        })

        result = select_one('SELECT `user_name` from users')
        result = result['user_name'] if result.respond_to?(:has_key?)
        value(result).must_equal('a user')
      end
    end

    it 'should raise an exception if the triggers do not exist after copying all rows' do
      table_create(:users)

      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm::Invoker.any_instance.stubs(:triggers_still_exist?).returns(false)

      exception = assert_raises do
        Lhm.change_table(:users) do |t|
          t.rename_column(:group, :fnord)
        end
      end

      assert_match "Verification failed, aborting early", exception.message
    end

    it 'should not perform the table rename if the triggers do not exist after copying all rows' do
      table_create(:users)

      execute("INSERT INTO users (username) VALUES ('a user')")

      Lhm::Invoker.any_instance.stubs(:triggers_still_exist?).returns(false)
      Lhm::LockedSwitcher.any_instance.expects(:run).never

      assert_raises do
        Lhm.change_table(:users) do |t|
          t.rename_column(:group, :fnord)
        end
      end

      replica do
        table_data = table_read(:users)
        assert_nil table_data.columns['fnord']
        value(table_read(:users).columns['group']).must_equal({
          :type => 'varchar(255)',
          :is_nullable => 'YES',
          :column_default => 'Superfriends',
          :comment => '',
          :collate => 'utf8_general_ci',
        })
      end
    end

    it 'works when mysql reserved words are used' do
      table_create(:lines)
      execute("insert into `lines` set id = 1, `between` = 'foo'")
      execute("insert into `lines` set id = 2, `between` = 'bar'")

      Lhm.change_table(:lines) do |t|
        t.add_column('by', 'varchar(10)')
        t.remove_column('lines')
        t.add_index('by')
        t.add_unique_index('between')
        t.remove_index('by')
      end

      replica do
        value(table_read(:lines).columns).must_include 'by'
        value(table_read(:lines).columns).wont_include 'lines'
        value(index_on_columns?(:lines, ['between'], :unique)).must_equal true
        value(index_on_columns?(:lines, ['by'])).must_equal false
        value(count_all(:lines)).must_equal(2)
      end
    end

    describe 'parallel' do
      it 'should perserve inserts during migration' do
        50.times { |n| execute("insert into users set reference = '#{ n }'") }

        insert = Thread.new do
          10.times do |n|
            connect_master!
            execute("insert into users set reference = '#{ 100 + n }'")
            sleep(0.17)
          end
        end
        sleep 2

        options = { :stride => 10, :throttle => 97, :atomic_switch => false }
        Lhm.change_table(:users, options) do |t|
          t.add_column(:parallel, "INT(10) DEFAULT '0'")
        end

        insert.join

        replica do
          value(count_all(:users)).must_equal(60)
        end
      end

      it 'should perserve deletes during migration' do
        50.times { |n| execute("insert into users set reference = '#{ n }'") }

        delete = Thread.new do
          10.times do |n|
            execute("delete from users where reference = '#{ n }'")
            sleep(0.17)
          end
        end
        sleep 2

        options = { :stride => 10, :throttle => 97, :atomic_switch => false }
        Lhm.change_table(:users, options) do |t|
          t.add_column(:parallel, "INT(10) DEFAULT '0'")
        end

        delete.join

        replica do
          value(count_all(:users)).must_equal(40)
        end
      end
    end

    describe 'connection' do
      include ToxiproxyHelper

      before(:each) do
        @logs = StringIO.new
        Lhm.logger = Logger.new(@logs)
      end

      it " should not try to reconnect if reconnect_with_consistent_host is not provided" do
        connect_master_with_toxiproxy!

        table_create(:users)
        100.times { |n| execute("insert into users set reference = '#{ n }'") }

        assert_raises ActiveRecord::StatementInvalid do
          Toxiproxy[:mysql_master].down do
            Lhm.change_table(:users, :atomic_switch => false) do |t|
              t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL")
              t.ddl("ALTER TABLE #{t.name} DROP PRIMARY KEY, ADD PRIMARY KEY (username, id)")
              t.ddl("ALTER TABLE #{t.name} ADD INDEX (id)")
              t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL AUTO_INCREMENT")
            end
          end
        end
      end

      it "should reconnect if reconnect_with_consistent_host is true" do
        connect_master_with_toxiproxy!
        mysql_disabled = false

        table_create(:users)
        100.times { |n| execute("insert into users set reference = '#{ n }'") }

        # Redeclare Lhm::ChunkInsert to use Hook to disable MySQL writer for 3 seconds before first insert
        Lhm::ChunkInsert.class_eval do
          extend AfterDo

          before(:insert_and_return_count_of_rows_created) do
            unless mysql_disabled
              mysql_disabled = true
              Thread.new do
                Toxiproxy[:mysql_master].down do
                  sleep 3
                end
              end
            end
          end

          # Need to call `#method_added` manually to have the hooks take into effect
          method_added(:insert_and_return_count_of_rows_created)
        end

        Lhm.change_table(:users, atomic_switch: false, reconnect_with_consistent_host: true) do |t|
          t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL")
          t.ddl("ALTER TABLE #{t.name} DROP PRIMARY KEY, ADD PRIMARY KEY (username, id)")
          t.ddl("ALTER TABLE #{t.name} ADD INDEX (id)")
          t.ddl("ALTER TABLE #{t.name} CHANGE id id bigint (20) NOT NULL AUTO_INCREMENT")
        end

        log_lines = @logs.string.split("\n")

        assert log_lines.one?{ |line| line.include?("Lost connection to MySQL, will retry to connect to same host")}
        assert log_lines.one?{ |line| line.include?("LHM successfully reconnected to initial host")}
        assert log_lines.one?{ |line| line.include?("100% complete")}

        Lhm::ChunkInsert.remove_all_callbacks

        replica do
          value(count_all(:users)).must_equal(100)
        end
      end
    end
  end
end
