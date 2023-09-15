require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'
require 'test_helper'

describe Lhm do
  include IntegrationHelper

  before(:each) do
    connect_master!
  end

  describe 'progress state' do
    it 'should make the final state setup_failed when failed to create shadow table' do
      table_create(:users)
      execute('create table lhmn_users(id int(11) NOT NULL)')

      exception = assert_raises(Lhm::Error) do
        Lhm.change_table(:users) do |t|
          t.add_column(:t1, "INT(11)")
        end
      end
      
      progress = Lhm.progress
      assert_equal progress.state, Lhm::STATE_SETUP_FAILED
    end
  end
end
