module Lhm
  module Throttler

    def self.format_hosts(hosts)
      formatted_hosts = []
      hosts.each do |host|
        if host && !host.match(/localhost/) && !host.match(/127.0.0.1/)
          formatted_hosts << host.partition(':')[0]
        end
      end
      formatted_hosts
    end

    class ReplicaLag
      include Command
      include BackoffReduction

      INITIAL_TIMEOUT = 0.1
      DEFAULT_STRIDE = 2_000
      DEFAULT_MAX_ALLOWED_LAG = 10

      MAX_TIMEOUT = INITIAL_TIMEOUT * 1024

      attr_accessor :timeout_seconds, :allowed_lag, :stride, :connection

      def initialize(options = {})
        @timeout_seconds = INITIAL_TIMEOUT
        @stride = options[:stride] || DEFAULT_STRIDE
        @allowed_lag = options[:allowed_lag] || DEFAULT_MAX_ALLOWED_LAG
        @replicas = {}
        @get_config = options[:current_config]
        @check_only = options[:check_only]

        super
      end

      def execute
        sleep(throttle_seconds)
      end

      private

      def throttle_seconds
        lag = max_current_replica_lag

        if lag > @allowed_lag && @timeout_seconds < MAX_TIMEOUT
          Lhm.logger.info("Increasing timeout between strides from #{@timeout_seconds} to #{@timeout_seconds * 2} because #{lag} seconds of replica lag detected is greater than the maximum of #{@allowed_lag} seconds allowed.")
          @timeout_seconds = @timeout_seconds * 2
        elsif lag <= @allowed_lag && @timeout_seconds > INITIAL_TIMEOUT
          Lhm.logger.info("Decreasing timeout between strides from #{@timeout_seconds} to #{@timeout_seconds / 2} because #{lag} seconds of replica lag detected is less than or equal to the #{@allowed_lag} seconds allowed.")
          @timeout_seconds = @timeout_seconds / 2
        else
          @timeout_seconds
        end
      end

      def replicas
        @replicas[@connection] ||= get_replicas
      end

      def get_replicas
        replicas = []
        if @check_only.nil? or !@check_only.respond_to?(:call)
          replica_hosts = master_replica_hosts
          while replica_hosts.any? do
            host = replica_hosts.pop
            replica = Replica.new(host, @get_config)
            if !replicas.map(&:host).include?(host) && replica.connection
              replicas << replica
              replica_hosts.concat(replica.replica_hosts)
            end
          end
        else
          replica_config = @check_only.call
          replicas << Replica.new(replica_config['host'], @get_config)
        end
        replicas
      end

      def master_replica_hosts
        Throttler.format_hosts(@connection.select_values(Replica::SQL_SELECT_REPLICA_HOSTS))
      end

      def max_current_replica_lag
        max = replicas.map { |replica| replica.lag }.push(0).max
        Lhm.logger.info "Max current replica lag: #{max}"
        max
      end
    end

    class Replica
      SQL_SELECT_REPLICA_HOSTS = "SELECT host FROM information_schema.processlist WHERE command LIKE 'Binlog Dump%'"
      SQL_SELECT_MAX_REPLICA_LAG = 'SHOW SLAVE STATUS'

      attr_reader :host, :connection

      def self.client
        defined?(Mysql2::Client) ? Mysql2::Client : Trilogy
      end

      def self.client_error
        defined?(Mysql2::Error) ? Mysql2::Error : Trilogy::Error
      end

      def initialize(host, connection_config = nil)
        @host = host
        @connection_config = prepare_connection_config(connection_config)
        @connection = client(@connection_config)
      end

      def replica_hosts
        Throttler.format_hosts(query_connection(SQL_SELECT_REPLICA_HOSTS, 'host'))
      end

      def lag
        query_connection(SQL_SELECT_MAX_REPLICA_LAG, 'Seconds_Behind_Master').first.to_i
      end

      private

      def client(config)
        Lhm.logger.info "Connecting to #{@host} on database: #{config[:database]}"
        self.class.client.new(config)
      rescue self.class.client_error => e
        Lhm.logger.info "Error connecting to #{@host}: #{e}"
        nil
      end

      def prepare_connection_config(config_proc)
        config = if config_proc
          if config_proc.respond_to?(:call) # if we get a proc
            config_proc.call
          else
            raise ArgumentError, "Expected #{config_proc.inspect} to respond to `call`"
          end
        else
          ActiveRecord::Base.connection_pool.db_config.configuration_hash.dup
        end
        config.deep_symbolize_keys!
        config[:host] = @host
        config
      end

      def query_connection(query, result)
        @connection.query(query).map { |row| row[result] }
      rescue self.class.client_error => e
        Lhm.logger.info "Unable to connect and/or query #{host}: #{e}"
        [nil]
      end
    end
  end
end
