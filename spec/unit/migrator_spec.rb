# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/table'
require 'lhm/migrator'

describe Lhm::Migrator do
  include UnitHelper

  before(:each) do
    @table = Lhm::Table.new('alt')
    @creator = Lhm::Migrator.new(@table)
  end

  describe 'index changes' do
    it 'should add an index' do
      @creator.add_index(:a)

      value(@creator.statements).must_equal([
        'create index `index_alt_on_a` on `lhmn_alt` (`a`)'
      ])
    end

    it 'should add a composite index' do
      @creator.add_index([:a, :b])

      value(@creator.statements).must_equal([
        'create index `index_alt_on_a_and_b` on `lhmn_alt` (`a`, `b`)'
      ])
    end

    it 'should add an index with prefix length' do
      @creator.add_index(['a(10)', 'b'])

      value(@creator.statements).must_equal([
        'create index `index_alt_on_a_and_b` on `lhmn_alt` (`a`(10), `b`)'
      ])
    end

    it 'should add an index with a custom name' do
      @creator.add_index([:a, :b], :custom_index_name)

      value(@creator.statements).must_equal([
        'create index `custom_index_name` on `lhmn_alt` (`a`, `b`)'
      ])
    end

    it 'should raise an error when the index name is not a string or symbol' do
      assert_raises ArgumentError do
        @creator.add_index([:a, :b], :name => :custom_index_name)
      end
    end

    it 'should add a unique index' do
      @creator.add_unique_index(['a(5)', :b])

      value(@creator.statements).must_equal([
        'create unique index `index_alt_on_a_and_b` on `lhmn_alt` (`a`(5), `b`)'
      ])
    end

    it 'should add a unique index with a custom name' do
      @creator.add_unique_index([:a, :b], :custom_index_name)

      value(@creator.statements).must_equal([
        'create unique index `custom_index_name` on `lhmn_alt` (`a`, `b`)'
      ])
    end

    it 'should raise an error when the unique index name is not a string or symbol' do
      assert_raises ArgumentError do
        @creator.add_unique_index([:a, :b], :name => :custom_index_name)
      end
    end

    it 'should remove an index' do
      @creator.remove_index(['b', 'a'])

      value(@creator.statements).must_equal([
        'drop index `index_alt_on_b_and_a` on `lhmn_alt`'
      ])
    end

    it 'should remove an index with a custom name' do
      @creator.remove_index([:a, :b], :custom_index_name)

      value(@creator.statements).must_equal([
        'drop index `custom_index_name` on `lhmn_alt`'
      ])
    end
  end

  describe 'column changes' do
    it 'should add a column' do
      @creator.add_column('logins', 'INT(12)')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` add column `logins` INT(12), ALGORITHM=INPLACE'
      ])
    end

    it 'should add a column using the passed algorithm' do
      @creator.add_column('logins', 'INT(12)', algorithm: 'COPY')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` add column `logins` INT(12), ALGORITHM=COPY'
      ])
    end

    it 'should remove a column' do
      @creator.remove_column('logins')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` drop `logins`, ALGORITHM=INPLACE'
      ])
    end

    it 'should remove a column using the passed algorithm' do
      @creator.remove_column('logins', algorithm: 'COPY')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` drop `logins`, ALGORITHM=COPY'
      ])
    end

    it 'should change a column' do
      @creator.change_column('logins', 'INT(11)')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` modify column `logins` INT(11)'
      ])
    end

    it "should drop a default" do
      @creator.change_column('foo', 'DROP DEFAULT')

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` alter column `foo` DROP DEFAULT'
      ])
    end

    it "should set a default" do
      @creator.change_column('foo', "SET DEFAULT 'bar'")

      value(@creator.statements).must_equal([
        "alter table `lhmn_alt` alter column `foo` SET DEFAULT 'bar'"
      ])
    end
  end

  describe 'direct changes' do
    it 'should accept a ddl statement' do
      @creator.ddl('alter table `%s` add column `f` tinyint(1)' % @creator.name)

      value(@creator.statements).must_equal([
        'alter table `lhmn_alt` add column `f` tinyint(1)'
      ])
    end
  end

  describe 'multiple changes' do
    it 'should add two columns' do
      @creator.add_column('first', 'VARCHAR(64)')
      @creator.add_column('last', 'VARCHAR(64)')
      value(@creator.statements.length).must_equal(2)

      value(@creator.statements[0])
        .must_equal('alter table `lhmn_alt` add column `first` VARCHAR(64), ALGORITHM=INPLACE')

      value(@creator.statements[1])
        .must_equal('alter table `lhmn_alt` add column `last` VARCHAR(64), ALGORITHM=INPLACE')
    end
  end

  describe 'multiple changes using the passed algorithm' do
    it 'should add two columns' do
      @creator.add_column('first', 'VARCHAR(64)', algorithm: 'COPY')
      @creator.add_column('last', 'VARCHAR(64)', algorithm: 'COPY')
      value(@creator.statements.length).must_equal(2)

      value(@creator.statements[0])
        .must_equal('alter table `lhmn_alt` add column `first` VARCHAR(64), ALGORITHM=COPY')

      value(@creator.statements[1])
        .must_equal('alter table `lhmn_alt` add column `last` VARCHAR(64), ALGORITHM=COPY')
    end
  end
end
