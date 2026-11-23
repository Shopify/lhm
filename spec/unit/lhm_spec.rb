# Copyright (c) 2011 - 2013, SoundCloud Ltd.

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

describe Lhm do

  before(:each) do
    Lhm.remove_class_variable :@@logger if Lhm.class_variable_defined? :@@logger
  end

  describe 'logger' do

    it 'should use the default parameters if no logger explicitly set' do
      value(Lhm.logger).must_be_kind_of Logger
      value(Lhm.logger.level).must_equal Logger::INFO
      value(Lhm.logger.instance_eval { @logdev }.dev).must_equal STDOUT
    end

    it 'should use s new logger if set' do
      l = Logger.new('omg.ponies')
      l.level = Logger::ERROR
      Lhm.logger = l

      value(Lhm.logger.level).must_equal Logger::ERROR
      value(Lhm.logger.instance_eval { @logdev }.dev).must_be_kind_of File
      value(Lhm.logger.instance_eval { @logdev }.dev.path).must_equal 'omg.ponies'
    end
  end

  describe 'api' do

    before(:each) do
      @connection = mock()
    end

    it 'should create a new connection when calling setup' do
      Lhm.setup(@connection)
      value(Lhm.connection).must_be_kind_of(Lhm::Connection)
    end

    it 'should create a new connection when none is created' do
      ActiveRecord::Base.stubs(:connection).returns(@connection)
      value(Lhm.connection).must_be_kind_of(Lhm::Connection)
    end
  end

  describe 'cleanup' do
    before(:each) do
      Lhm.logger = Logger.new(StringIO.new)
      @connection = mock()
      Lhm.stubs(:connection).returns(@connection)
    end

    it 'should quote each table and trigger name it drops' do
      @connection.stubs(:select_values).with('show tables').returns(['users', 'lhmn_a, b', 'lhma_b`c'])
      @connection.stubs(:select_values).with('show triggers').returns(['lhmt_ins_users', 'lhmt_d e'])

      drops = sequence('drops')
      @connection.expects(:execute).with('drop trigger if exists `lhmt_ins_users`').in_sequence(drops)
      @connection.expects(:execute).with('drop trigger if exists `lhmt_d e`').in_sequence(drops)
      @connection.expects(:execute).with('drop table if exists `lhmn_a, b`').in_sequence(drops)
      @connection.expects(:execute).with('drop table if exists `lhma_b``c`').in_sequence(drops)

      value(Lhm.cleanup(true)).must_equal(true)
    end

    it 'should drop nothing when it does not run' do
      @connection.stubs(:select_values).with('show tables').returns(['lhmn_a, b'])
      @connection.stubs(:select_values).with('show triggers').returns(['lhmt_d e'])
      @connection.expects(:execute).never

      value(Lhm.cleanup(false)).must_equal(false)
    end
  end

  describe 'cleanup_current_run' do
    before(:each) do
      Lhm.logger = Logger.new(StringIO.new)
      @connection = mock()
      Lhm.stubs(:connection).returns(@connection)
    end

    it 'should quote each trigger and table name in its statements' do
      @connection.stubs(:select_values).with("show triggers like '%users'").returns(['lhmt_ins_users', 'lhmt_d e_users', 'other_users'])
      @connection.stubs(:select_values).with("show tables like 'lhmn_users'").returns(['lhmn_users'])

      statements = []
      @connection.stubs(:execute).with { |sql, **_| statements << sql }

      assert Lhm.cleanup_current_run(true, 'users')

      value(statements[0]).must_equal('drop trigger if exists `lhmt_ins_users`')
      value(statements[1]).must_equal('drop trigger if exists `lhmt_d e_users`')
      value(statements[2]).must_match(/\Arename table `lhmn_users` to `lhma_[0-9_]+_users_failed`\z/)
      value(statements.length).must_equal(3)
    end
  end
end
