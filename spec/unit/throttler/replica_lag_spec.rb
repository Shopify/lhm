require File.expand_path(File.dirname(__FILE__)) + '/../unit_helper'

require 'lhm/throttler/replica_lag'

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

    describe 'with only nil hosts' do
      it 'returns no hosts' do
        assert_equal([], Lhm::Throttler.format_hosts([nil]))
      end
    end

    describe 'with some nil hosts' do
      it 'returns the remaining hosts' do
        assert_equal(['server.example.com'], Lhm::Throttler.format_hosts([nil, 'server.example.com:1234']))
      end
    end
  end
end

describe Lhm::Throttler::Replica do
  include UnitHelper

  before :each do
    @logs = StringIO.new
    Lhm.logger = Logger.new(@logs)

    @dummy_mysql_client_config = lambda { { 'username' => 'user', 'password' => 'pw', 'database' => 'db' } }
  end

  describe "#client" do
    describe 'on connection error' do
      it 'logs and returns nil' do
        assert_nil(Lhm::Throttler::Replica.new('replica', @dummy_mysql_client_config).connection)

        log_messages = @logs.string.lines
        assert_equal(2, log_messages.length)
        assert log_messages[0].include? "Connecting to replica on database: db"
        assert log_messages[1].include? "Error connecting to replica"
      end
    end

    describe 'with proper config' do
      it "creates a new database client" do
        expected_config = { username: 'user', password: 'pw', database: 'db', host: 'replica' }
        DATABASE.client.stubs(:new).with(expected_config).returns(mock())

        assert Lhm::Throttler::Replica.new('replica', @dummy_mysql_client_config).connection
      end
    end

    describe 'with active record config' do
      it 'logs and creates client' do
        active_record_config = { username: 'user', password: 'pw', database: 'db' }
        ActiveRecord::Base.stubs(:connection_pool).returns(stub(db_config: stub(configuration_hash: active_record_config)))

        DATABASE.client.stubs(:new).returns(mock())

        assert Lhm::Throttler::Replica.new('replica').connection

        log_messages = @logs.string.lines
        assert_equal(1, log_messages.length)
        assert log_messages[0].include? "Connecting to replica on database: db"
      end
    end
  end

  describe "#connection" do
    before do
      class Connection
        def self.query(query)
          if query == Lhm::Throttler::Replica::SQL_SELECT_MAX_REPLICA_LAG
            [{ 'Seconds_Behind_Master' => 20 }]
          elsif query == Lhm::Throttler::Replica::SQL_SELECT_REPLICA_HOSTS
            [{ 'host' => '1.1.1.1:80' }]
          end
        end
      end

      @replica = Lhm::Throttler::Replica.new('replica', @dummy_mysql_client_config)
      @replica.instance_variable_set(:@connection, Connection)

      class StoppedConnection
        def self.query(query)
          [{ 'Seconds_Behind_Master' => nil }]
        end
      end

      @stopped_replica = Lhm::Throttler::Replica.new('stopped_replica', @dummy_mysql_client_config)
      @stopped_replica.instance_variable_set(:@connection, StoppedConnection)
    end

    describe "#lag" do
      it "returns the replica lag" do
        assert_equal(20, @replica.lag)
      end
    end

    describe "#lag with a stopped replica" do
      it "returns 0 replica lag" do
        assert_equal(0, @stopped_replica.lag)
      end
    end

    describe "#replica_hosts" do
      it "returns the hosts" do
        assert_equal(['1.1.1.1'], @replica.replica_hosts)
      end
    end

    describe "#lag on connection error" do
      it "logs and returns 0 replica lag" do
        client = mock()
        client.stubs(:query).raises(DATABASE.error_class, "Can't connect to MySQL server")
        Lhm::Throttler::Replica.any_instance.stubs(:client).returns(client)
        Lhm::Throttler::Replica.any_instance.stubs(:config).returns([])

        replica = Lhm::Throttler::Replica.new('replica', @dummy_mysql_client_config)
        Logger.any_instance.expects(:info).with("Unable to connect and/or query replica: Can't connect to MySQL server")
        assert_equal(0, replica.lag)
      end
    end
  end
end

describe Lhm::Throttler::ReplicaLag do
  include UnitHelper

  before :each do
    @throttler = Lhm::Throttler::ReplicaLag.new
  end

  describe '#throttle_seconds' do
    describe 'with no replica lag' do
      before do
        def @throttler.max_current_replica_lag
          0
        end
      end

      it 'does not alter the currently set timeout' do
        timeout = @throttler.timeout_seconds
        assert_equal(timeout, @throttler.send(:throttle_seconds))
      end
    end

    describe 'with a large replica lag' do
      before do
        def @throttler.max_current_replica_lag
          100
        end
      end

      it 'doubles the currently set timeout' do
        timeout = @throttler.timeout_seconds
        assert_equal(timeout * 2, @throttler.send(:throttle_seconds))
      end

      it 'does not increase the timeout past the maximum' do
        @throttler.timeout_seconds = Lhm::Throttler::ReplicaLag::MAX_TIMEOUT
        assert_equal(Lhm::Throttler::ReplicaLag::MAX_TIMEOUT, @throttler.send(:throttle_seconds))
      end
    end

    describe 'with no replica lag after it has previously been increased' do
      before do
        def @throttler.max_current_replica_lag
          0
        end
      end

      it 'halves the currently set timeout' do
        @throttler.timeout_seconds *= 2 * 2
        timeout = @throttler.timeout_seconds
        assert_equal(timeout / 2, @throttler.send(:throttle_seconds))
      end

      it 'does not decrease the timeout past the minimum on repeated runs' do
        @throttler.timeout_seconds = Lhm::Throttler::ReplicaLag::INITIAL_TIMEOUT * 2
        assert_equal(Lhm::Throttler::ReplicaLag::INITIAL_TIMEOUT, @throttler.send(:throttle_seconds))
        assert_equal(Lhm::Throttler::ReplicaLag::INITIAL_TIMEOUT, @throttler.send(:throttle_seconds))
      end
    end
  end

  describe '#max_current_replica_lag' do
    describe 'with multiple replicas' do
      it 'returns the largest amount of lag' do
        replica1 = mock()
        replica2 = mock()
        replica1.stubs(:lag).returns(5)
        replica2.stubs(:lag).returns(0)
        Lhm::Throttler::ReplicaLag.any_instance.stubs(:replicas).returns([replica1, replica2])
        assert_equal 5, @throttler.send(:max_current_replica_lag)
      end
    end

    describe 'with MySQL stopped on the replica' do
      it 'assumes 0 replica lag' do
        client = mock()
        client.stubs(:query).raises(DATABASE.error_class, "Can't connect to MySQL server")
        Lhm::Throttler::Replica.any_instance.stubs(:client).returns(client)

        Lhm::Throttler::Replica.any_instance.stubs(:prepare_connection_config).returns([])
        Lhm::Throttler::Replica.any_instance.stubs(:replica_hosts).returns(['1.1.1.2'])
        @throttler.stubs(:master_replica_hosts).returns(['1.1.1.1'])

        assert_equal 0, @throttler.send(:max_current_replica_lag)
      end
    end
  end

  describe '#get_replicas' do
    describe 'with no replicas' do
      before do
        def @throttler.master_replica_hosts
          []
        end
      end

      it 'returns no replicas' do
        assert_equal([], @throttler.send(:get_replicas))
      end
    end

    describe 'with multiple replicas' do
      before do
        class TestReplica
          attr_reader :host, :connection

          def initialize(host, _)
            @host = host
            @connection = 'conn' if @host
          end

          def replica_hosts
            if @host == '1.1.1.1'
              ['1.1.1.2', '1.1.1.3']
            else
              [nil]
            end
          end
        end

        @create_replica = lambda { |host, config|
          TestReplica.new(host, config)
        }
      end

      describe 'without the :check_only option' do
        before do
          def @throttler.master_replica_hosts
            ['1.1.1.1', '1.1.1.4']
          end
        end

        it 'returns the replica instances' do
          Lhm::Throttler::Replica.stubs(:new).returns(@create_replica) do
            assert_equal(["1.1.1.4", "1.1.1.1", "1.1.1.3", "1.1.1.2"], @throttler.send(:get_replicas).map(&:host))
          end
        end
      end

      describe 'with the :check_only option' do
        describe 'with a callable argument' do
          before do
            check_only = lambda { { 'host' => '1.1.1.3' } }
            @throttler = Lhm::Throttler::ReplicaLag.new :check_only => check_only
          end

          it 'returns only that single replica' do
            Lhm::Throttler::Replica.stubs(:new).returns(@create_replica) do
              assert_equal ['1.1.1.3'], @throttler.send(:get_replicas).map(&:host)
            end
          end
        end

        describe 'with a non-callable argument' do
          before do
            @throttler = Lhm::Throttler::ReplicaLag.new :check_only => 'I cannot be called'

            def @throttler.master_replica_hosts
              ['1.1.1.1', '1.1.1.4']
            end
          end

          it 'returns all the replica instances' do
            Lhm::Throttler::Replica.stubs(:new).returns(@create_replica) do
              assert_equal(["1.1.1.4", "1.1.1.1", "1.1.1.3", "1.1.1.2"], @throttler.send(:get_replicas).map(&:host))
            end
          end
        end
      end
    end
  end
end
