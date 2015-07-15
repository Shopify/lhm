require File.expand_path(File.dirname(__FILE__)) + '/../unit_helper'

require 'lhm/throttler/slave_lag'

describe Lhm::Throttler do
  include UnitHelper

  describe '#format_hosts' do
    describe 'with only localhost hosts' do
      it 'returns no hosts' do
        assert_equal([], Lhm::Throttler.format_hosts(['localhost:1234', '127.0.0.1:5678']))
      end
    end

    describe 'with only remote hosts' do
      it 'returns remote hosts' do
        assert_equal(['server.example.com', 'anotherserver.example.com'], Lhm::Throttler.format_hosts(['server.example.com:1234', 'anotherserver.example.com']))
      end
    end
  end
end

describe Lhm::Throttler::Slave do
  include UnitHelper

  before :each do
    def get_config
      lambda { {'username' => 'user', 'password' => 'pw', 'database' => 'db'} }
    end
  end

  describe "#client" do
    before do
      class TestMysql2Client
        def initialize(config)
          raise Mysql2::Error.new("connection error")
        end
      end
    end

    describe 'on connection error' do
      it 'logs and returns nil' do
        test_client = lambda { |config|
          TestMysql2Client.new(config)
        }
        Mysql2::Client.stub :new, test_client do
          assert_send([Lhm.logger, :info, "Error connecting to slave: connection error"])
          assert_nil(Lhm::Throttler::Slave.new('slave', lambda { {} }).connection)
        end
      end
    end

    describe 'with proper config' do
      it "creates a new Mysql2::Client" do
        client_assertion = lambda { |config|
          assert_equal(config, {:host => 'slave', :username => 'user', :password => 'pw', :database => 'db'})
        }
        Mysql2::Client.stub :new, client_assertion do
          Lhm::Throttler::Slave.new('slave', get_config)
        end
      end
    end
  end

  describe "#connection" do
    before do
      class Connection
        def self.query(query)
          if query == Lhm::Throttler::Slave::SQL_SELECT_MAX_SLAVE_LAG
            [{'Seconds_Behind_Master' => 20}]
          elsif query == Lhm::Throttler::Slave::SQL_SELECT_SLAVE_HOSTS
            [{'host' => '1.1.1.1:80'}]
          end
        end
      end

      @slave = Lhm::Throttler::Slave.new('slave', get_config)
      @slave.instance_variable_set(:@connection, Connection)
    end

    describe "#lag" do
      it "returns the slave lag" do
        assert_equal([20], @slave.lag)
      end
    end

    describe "#slave_hosts" do
      it "returns the hosts" do
        assert_equal(['1.1.1.1'], @slave.slave_hosts)
      end
    end
  end
end

describe Lhm::Throttler::SlaveLag do
  include UnitHelper

  before :each do
    @throttler = Lhm::Throttler::SlaveLag.new
  end

  describe '#throttle_seconds' do
    describe 'with no slave lag' do
      before do
        def @throttler.max_current_slave_lag
          0
        end
      end

      it 'does not alter the currently set timeout' do
        timeout = @throttler.timeout_seconds
        assert_equal(timeout, @throttler.send(:throttle_seconds))
      end
    end

    describe 'with a large slave lag' do
      before do
        def @throttler.max_current_slave_lag
          100
        end
      end

      it 'doubles the currently set timeout' do
        timeout = @throttler.timeout_seconds
        assert_equal(timeout * 2, @throttler.send(:throttle_seconds))
      end

      it 'does not increase the timeout past the maximum' do
        @throttler.timeout_seconds = Lhm::Throttler::SlaveLag::MAX_TIMEOUT
        assert_equal(Lhm::Throttler::SlaveLag::MAX_TIMEOUT, @throttler.send(:throttle_seconds))
      end
    end

    describe 'with no slave lag after it has previously been increased' do
      before do
        def @throttler.max_current_slave_lag
          0
        end
      end

      it 'halves the currently set timeout' do
        @throttler.timeout_seconds *= 2 * 2
        timeout = @throttler.timeout_seconds
        assert_equal(timeout / 2, @throttler.send(:throttle_seconds))
      end

      it 'does not decrease the timeout past the minimum on repeated runs' do
        @throttler.timeout_seconds = Lhm::Throttler::SlaveLag::INITIAL_TIMEOUT * 2
        assert_equal(Lhm::Throttler::SlaveLag::INITIAL_TIMEOUT, @throttler.send(:throttle_seconds))
        assert_equal(Lhm::Throttler::SlaveLag::INITIAL_TIMEOUT, @throttler.send(:throttle_seconds))
      end
    end
  end

  describe '#get_slaves' do
    describe 'with no slaves' do
      before do
        def @throttler.master_slave_hosts
          []
        end
      end

      it 'returns no slaves' do
        assert_equal([], @throttler.send(:get_slaves))
      end
    end

    describe 'with multiple slaves' do
      before do
        class TestSlave
          attr_reader :host, :connection

          def initialize(host, get_config)
            @host = host
            @connection = 'conn' if @host
          end

          def slave_hosts
            if @host == '1.1.1.1'
              ['1.1.1.2', '1.1.1.3']
            else
              nil
            end
          end
        end

        def @throttler.master_slave_hosts
          ['1.1.1.1', '1.1.1.4']
        end
      end

      it 'returns the slave instances' do
        create_slave = lambda { |host, config|
          TestSlave.new(host, config)
        }
        Lhm::Throttler::Slave.stub :new, create_slave do
          assert_equal(["1.1.1.4", "1.1.1.1", "1.1.1.3", "1.1.1.2"], @throttler.send(:get_slaves).map(&:host))
        end
      end
    end
  end
end
