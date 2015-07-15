module Lhm
  module Throttler

    def self.format_hosts(hosts)
      hosts.map { |host| host.partition(':')[0] }
        .delete_if { |host| host == 'localhost' || host == '127.0.0.1' }
    end

    class SlaveLag
      include Command

      INITIAL_TIMEOUT = 0.1
      DEFAULT_STRIDE = 40_000
      DEFAULT_MAX_ALLOWED_LAG = 10

      MAX_TIMEOUT = INITIAL_TIMEOUT * 1024

      attr_accessor :timeout_seconds, :allowed_lag, :stride, :connection

      def initialize(options = {})
        @timeout_seconds = INITIAL_TIMEOUT
        @stride = options[:stride] || DEFAULT_STRIDE
        @allowed_lag = options[:allowed_lag] || DEFAULT_MAX_ALLOWED_LAG
        @slaves = {}
        @get_config = options[:current_config]
      end

      def execute
        sleep(throttle_seconds)
      end

      private

      def throttle_seconds
        lag = max_current_slave_lag

        if lag > @allowed_lag && @timeout_seconds < MAX_TIMEOUT
          Lhm.logger.info("Increasing timeout between strides from #{@timeout_seconds} to #{@timeout_seconds * 2} because #{lag} seconds of slave lag detected is greater than the maximum of #{@allowed_lag} seconds allowed.")
          @timeout_seconds = @timeout_seconds * 2
        elsif lag <= @allowed_lag && @timeout_seconds > INITIAL_TIMEOUT
          Lhm.logger.info("Decreasing timeout between strides from #{@timeout_seconds} to #{@timeout_seconds / 2} because #{lag} seconds of slave lag detected is less than or equal to the #{@allowed_lag} seconds allowed.")
          @timeout_seconds = @timeout_seconds / 2
        else
          @timeout_seconds
        end
      end

      def slaves
        @slaves[@connection] ||= get_slaves
      end

      def get_slaves
        slaves = []
        slave_hosts = master_slave_hosts
        Lhm.logger.info("master_slave_hosts: #{master_slave_hosts}")
        while slave_hosts.any? do
          host = slave_hosts.pop
          Lhm.logger.info("host: #{host}")
          slave = Slave.new(host, @get_config)
          if slaves.map(&:host).exclude?(host) && slave.connection
            Lhm.logger.info("slave.slave_hosts: #{slave.slave_hosts}")
            slaves << slave
            slave_hosts << slave.slave_hosts
            slave_hosts.flatten!
          end
        end
        Lhm.logger.info("!!!!!!!!!!! FINAL SLAVES: #{slaves.map(&:host)}")
        slaves
      end

      def master_slave_hosts
        Throttler.format_hosts(@connection.select_values(Slave::SQL_SELECT_SLAVE_HOSTS))
      end

      def max_current_slave_lag
        max = slaves.map { |slave| slave.lag }.flatten.push(0).max
        Lhm.logger.info "Max current slave lag: #{max}"
        max
      end
    end

    class Slave
      SQL_SELECT_SLAVE_HOSTS = "SELECT host FROM information_schema.processlist WHERE command='Binlog Dump'"
      SQL_SELECT_MAX_SLAVE_LAG = 'SHOW SLAVE STATUS'

      attr_reader :host, :connection

      def initialize(host, get_config=nil)
        @host = host
        @connection = client(config(get_config))
      end

      def slave_hosts
        Throttler.format_hosts(query_connection(SQL_SELECT_SLAVE_HOSTS, 'host'))
      end

      def lag
        lag = query_connection(SQL_SELECT_MAX_SLAVE_LAG, 'Seconds_Behind_Master')
        Lhm.logger.info "CALCULATED LAG #{lag} FOR #{@host}"
        lag
      end

      private

      def client(config)
        begin
          Mysql2::Client.new(config)
        rescue Mysql2::Error => e
          Lhm.logger.info "Error conecting to #{@host}: #{e}"
          nil
        end
      end

      def config(get_config)
        attrs = get_config ? get_config.call : ActiveRecord::Base.connection_pool.spec.config.dup
        {
          :host => @host,
          :username => attrs['username'],
          :password => attrs['password'],
          :database => attrs['database']
        }
      end

      def query_connection(query, result)
        begin
          @connection.query(query).map { |row| row[result] }
        rescue Error => e
          raise Lhm::Error, "Unable to connect and/or query slave to determine slave lag. Migration aborting because of: #{e}"
        end
      end
    end
  end
end
