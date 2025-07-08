# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/table'
require 'lhm/migration'
require 'lhm/entangler'
require 'lhm/connection'

describe Lhm::Entangler do
  include UnitHelper

  before(:each) do
    @origin = Lhm::Table.new('origin')
    @destination = Lhm::Table.new('destination')
    @migration = Lhm::Migration.new(@origin, @destination)
    @entangler = Lhm::Entangler.new(@migration)
  end

  describe 'activation' do
    before(:each) do
      @origin.columns['info'] = { :type => 'varchar(255)' }
      @origin.columns['tags'] = { :type => 'varchar(255)' }

      @destination.columns['info'] = { :type => 'varchar(255)' }
      @destination.columns['tags'] = { :type => 'varchar(255)' }
    end

    it 'should create the delete trigger to the destination table first' do
      ddl = %Q{
        create trigger `lhmt_del_origin`
        after delete on `origin` for each row
        delete ignore from `destination` /* large hadron migration */
        where `destination`.`id` = OLD.`id`
      }

      assert_equal strip(ddl), @entangler.entangle[0]
    end

    it 'should create the update trigger to the destination table second' do
      ddl = %Q{
        create trigger `lhmt_upd_origin`
        after update on `origin` for each row
        replace into `destination` (`info`, `tags`) /* large hadron migration */
        values (`NEW`.`info`, `NEW`.`tags`)
      }

      assert_equal strip(ddl), @entangler.entangle[1]
    end

    it 'should create the insert trigger to destination table last' do
      ddl = %Q{
        create trigger `lhmt_ins_origin`
        after insert on `origin` for each row
        replace into `destination` (`info`, `tags`) /* large hadron migration */
        values (`NEW`.`info`, `NEW`.`tags`)
      }

      assert_equal strip(ddl), @entangler.entangle[2]
    end

    it 'should retry trigger creation when it hits a lock wait timeout' do
      tries = 1
      ar_connection = mock()
      ar_connection.stubs(:select_value).returns("dummy")
      ar_connection.stubs(:execute)
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction')
      ar_connection.stubs(:active?).returns(true)

      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          base_interval: 0,
          tries: tries
        }
      })

      @entangler = Lhm::Entangler.new(@migration, connection)

      assert_raises(ActiveRecord::StatementInvalid) { @entangler.before }
    end

    it 'should not retry trigger creation with other mysql errors' do
      ar_connection = mock()
      ar_connection.stubs(:select_value).returns("dummy")
      ar_connection.stubs(:execute)
                   .raises(DATABASE.error_class, 'The MySQL server is running with the --read-only option so it cannot execute this statement.')
      ar_connection.stubs(:active?).returns(true)
      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          base_interval: 0
        },
      })

      @entangler = Lhm::Entangler.new(@migration, connection)
      assert_raises(DATABASE.error_class) { @entangler.before }
    end

    it 'should succesfully finish after retrying' do
      ar_connection = mock()
      ar_connection.stubs(:select_value).returns("dummy")
      ar_connection.stubs(:execute)
                   .raises(ActiveRecord::StatementInvalid, 'Lock wait timeout exceeded; try restarting transaction')
                   .then
                   .returns([["dummy"]])
      ar_connection.stubs(:active?).returns(true)

      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          base_interval: 0
        },
      })

      @entangler = Lhm::Entangler.new(@migration, connection)

      assert @entangler.before
    end

    it 'should retry as many times as specified by configuration' do
      ar_connection = mock()
      ar_connection.stubs(:select_value).returns("dummy")
      ar_connection.stubs(:execute)
                   .raises(DATABASE.error_class, 'Lock wait timeout exceeded; try restarting transaction')
                   .then
                   .raises(DATABASE.error_class, 'Lock wait timeout exceeded; try restarting transaction')
                   .then
                   .raises(DATABASE.error_class, 'Lock wait timeout exceeded; try restarting transaction')
                   .then
                   .raises(DATABASE.error_class, 'Lock wait timeout exceeded; try restarting transaction')  # final error
      ar_connection.stubs(:active?).returns(true)

      connection = Lhm::Connection.new(connection: ar_connection, options: {
        reconnect_with_consistent_host: true,
        retriable: {
          tries: 5,
          base_interval: 0
        },
      })

      @entangler = Lhm::Entangler.new(@migration, connection)

      assert_raises(DATABASE.error_class) { @entangler.before }
    end

    describe 'super long table names' do
      before(:each) do
        @origin = Lhm::Table.new('a' * 64)
        @destination = Lhm::Table.new('b' * 64)
        @migration = Lhm::Migration.new(@origin, @destination)
        @entangler = Lhm::Entangler.new(@migration)
      end

      it 'should use truncated names' do
        value(@entangler.trigger(:ins).length).must_be :<=, 64
        value(@entangler.trigger(:upd).length).must_be :<=, 64
        value(@entangler.trigger(:del).length).must_be :<=, 64
      end
    end
  end

  describe 'removal' do
    it 'should remove insert trigger' do
      value(@entangler.untangle).must_include('drop trigger if exists `lhmt_ins_origin`')
    end

    it 'should remove update trigger' do
      value(@entangler.untangle).must_include('drop trigger if exists `lhmt_upd_origin`')
    end

    it 'should remove delete trigger' do
      value(@entangler.untangle).must_include('drop trigger if exists `lhmt_del_origin`')
    end
  end
end
