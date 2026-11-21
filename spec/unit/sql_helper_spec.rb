# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

require 'lhm/sql_helper'

describe Lhm::SqlHelper do
  it 'should name index with a single column' do
    value(Lhm::SqlHelper.idx_name(:users, :name))
      .must_equal('index_users_on_name')
  end

  it 'should name index with multiple columns' do
    value(Lhm::SqlHelper.idx_name(:users, [:name, :firstname]))
      .must_equal('index_users_on_name_and_firstname')
  end

  it 'should name index with prefixed column' do
    value(Lhm::SqlHelper.idx_name(:tracks, ['title(10)', 'album']))
      .must_equal('index_tracks_on_title_and_album')
  end

  it 'should quote column names in index specification' do
    value(Lhm::SqlHelper.idx_spec(['title(10)', 'name (6)', 'album']))
      .must_equal('`title`(10), `name`(6), `album`')
  end

  it 'should quote an identifier' do
    value(Lhm::SqlHelper.quote_identifier('lhma_2026_01_01_00_00_00_000_users'))
      .must_equal('`lhma_2026_01_01_00_00_00_000_users`')
  end

  it 'should keep commas, spaces and dots inside one quoted identifier' do
    value(Lhm::SqlHelper.quote_identifier('lhmn_a, b.c'))
      .must_equal('`lhmn_a, b.c`')
  end

  it 'should escape backticks in an identifier' do
    value(Lhm::SqlHelper.quote_identifier('lhmn_a`b'))
      .must_equal('`lhmn_a``b`')
  end
end
