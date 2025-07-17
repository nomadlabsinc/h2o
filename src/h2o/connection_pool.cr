require "./types"
require "./protocol_negotiator"

module H2O
  # Connection pool manager following SRP principles
  # Manages connection lifecycle, scoring, and pooling for HTTP/1.1 and HTTP/2 connections
  class ConnectionPool
    # Configuration constants for connection health and lifecycle management
    private HEALTHY_SCORE_THRESHOLD = 60.0
    private MAX_IDLE_TIME           = 5.minutes
    private MAX_CONNECTION_AGE      = 1.hour

    # Enhanced connection metadata for scoring and lifecycle management
    private class ConnectionMetadata
      property connection : BaseConnection
      property created_at : Time
      property last_used : Time
      property request_count : Int32
      property error_count : Int32
      property avg_response_time : Float64
      property score : Float64

      def initialize(@connection : BaseConnection)
        @created_at = Time.utc
        @last_used = Time.utc
        @request_count = 0
        @error_count = 0
        @avg_response_time = 0.0
        @score = 100.0
      end

      def update_usage(success : Bool, response_time : Time::Span) : Nil
        @last_used = Time.utc
        @request_count += 1

        if success
          # Update rolling average response time
          new_time = response_time.total_milliseconds
          @avg_response_time = (@avg_response_time * (@request_count - 1) + new_time) / @request_count
        else
          @error_count += 1
        end

        calculate_score
      end

      def calculate_score : Nil
        # Base score starts at 100
        base_score = 100.0

        # Penalty for errors (up to -50 points)
        error_rate = @request_count > 0 ? @error_count.to_f64 / @request_count.to_f64 : 0.0
        error_penalty = error_rate * 50.0

        # Penalty for slow responses (up to -30 points)
        speed_penalty = Math.min(@avg_response_time / 1000.0 * 10.0, 30.0)

        # Bonus for established connections (up to +20 points)
        connection_age = Time.utc - @created_at
        age_bonus = Math.min(connection_age.total_minutes / 10.0, 20.0)

        @score = base_score - error_penalty - speed_penalty + age_bonus
      end

      def idle_time : Time::Span
        Time.utc - @last_used
      end
    end

    @connections : ConnectionsHash
    @connection_metadata : Hash(String, ConnectionMetadata)
    @warmup_hosts : Set(String)
    @pool_size : Int32
    @verify_ssl : Bool
    @protocol_negotiator : ProtocolNegotiator?
    @mutex : Mutex

    def initialize(@pool_size : Int32 = 10, @verify_ssl : Bool = true, @protocol_negotiator : ProtocolNegotiator? = nil)
      @connections = ConnectionsHash.new
      @connection_metadata = Hash(String, ConnectionMetadata).new
      @warmup_hosts = Set(String).new
      @mutex = Mutex.new
    end

    # Get or create a connection for the given host and port
    def get_connection(host : String, port : Int32, use_tls : Bool = true) : BaseConnection
      @mutex.synchronize do
        connection_key = "#{host}:#{port}"

        # Try to reuse existing healthy connection
        if existing_connection = get_healthy_connection(connection_key)
          return existing_connection
        end

        # Create new connection if pool has space or replace worst connection
        create_or_replace_connection(host, port, use_tls, connection_key)
      end
    end

    # Return a connection to the pool after use
    def return_connection(connection : BaseConnection, success : Bool, response_time : Time::Span) : Nil
      @mutex.synchronize do
        connection_key = find_connection_key(connection)
        return unless connection_key

        metadata = @connection_metadata[connection_key]?
        return unless metadata

        metadata.update_usage(success, response_time)
      end
    end

    # Pre-warm connection to frequently used hosts
    def warmup_connection(host : String, port : Int32 = 443) : Nil
      already_warming = @mutex.synchronize do
        return true if @warmup_hosts.includes?(host)
        @warmup_hosts.add(host)
        false
      end

      return if already_warming

      spawn do
        begin
          connection = get_connection(host, port)
          Log.info { "Warmed up connection to #{host}:#{port}" }
        rescue ex
          Log.warn { "Failed to warm up connection to #{host}:#{port}: #{ex.message}" }
          @mutex.synchronize { @warmup_hosts.delete(host) }
        end
      end
    end

    # Close all connections and clear the pool
    def close : Nil
      @mutex.synchronize do
        @connections.each_value(&.close)
        @connections.clear
        @connection_metadata.clear
        @warmup_hosts.clear
      end
    end

    # Check if connection is healthy and reusable
    def connection_healthy?(connection : BaseConnection) : Bool
      return false unless connection

      # Check age limit (1 hour max)
      connection_key = find_connection_key(connection)
      return false unless connection_key

      metadata = @connection_metadata[connection_key]?
      return false unless metadata

      age = Time.utc - metadata.created_at
      return false if age > MAX_CONNECTION_AGE

      # Check score threshold
      return false if metadata.score < HEALTHY_SCORE_THRESHOLD

      # Check idle timeout
      return false if metadata.idle_time > MAX_IDLE_TIME

      # Connection type specific checks
      case connection
      when H2::Client
        # HTTP/2 specific health checks
        return false if connection.closed
      when H1::Client
        # HTTP/1.1 specific health checks
        return false if connection.closed
      end

      true
    end

    # Get connection statistics
    def statistics : Hash(Symbol, Int32 | Float64)
      @mutex.synchronize do
        total_connections = @connections.size
        total_requests = @connection_metadata.values.sum(&.request_count)
        total_errors = @connection_metadata.values.sum(&.error_count)
        avg_score = @connection_metadata.values.sum(&.score) / Math.max(total_connections, 1)

        {
          :total_connections => total_connections,
          :pool_size         => @pool_size,
          :total_requests    => total_requests,
          :total_errors      => total_errors,
          :error_rate        => total_requests > 0 ? total_errors.to_f64 / total_requests.to_f64 : 0.0,
          :avg_score         => avg_score,
          :warmup_hosts      => @warmup_hosts.size,
        }
      end
    end

    # Set batch processing for all HTTP/2 connections
    def set_batch_processing(enabled : Bool) : Nil
      @mutex.synchronize do
        @connections.each_value do |connection|
          if connection.is_a?(H2::Client)
            connection.set_batch_processing(enabled)
          end
        end
      end
    end

    # Remove expired connections and clean up metadata
    def cleanup_expired_connections : Nil
      @mutex.synchronize do
        expired_keys = [] of String

        @connection_metadata.each do |key, metadata|
          if metadata.idle_time > MAX_IDLE_TIME || (Time.utc - metadata.created_at) > MAX_CONNECTION_AGE
            expired_keys << key
          end
        end

        expired_keys.each do |key|
          if connection = @connections[key]?
            connection.close
            @connections.delete(key)
            @connection_metadata.delete(key)
          end
        end
      end
    end

    # Get pool utilization rate
    def utilization_rate : Float64
      @mutex.synchronize do
        @connections.size.to_f64 / @pool_size.to_f64
      end
    end

    # Check if pool is full
    def pool_full? : Bool
      @mutex.synchronize do
        pool_full_unsafe?
      end
    end

    # Check if pool is full (assumes mutex is already held)
    private def pool_full_unsafe? : Bool
      @connections.size >= @pool_size
    end

    private def get_healthy_connection(connection_key : String) : BaseConnection?
      existing_connection = @connections[connection_key]?
      return nil unless existing_connection

      if connection_healthy?(existing_connection)
        existing_connection
      else
        # Remove unhealthy connection
        remove_connection(connection_key)
        nil
      end
    end

    private def create_or_replace_connection(host : String, port : Int32, use_tls : Bool, connection_key : String) : BaseConnection
      # If pool is full, remove the worst connection
      if pool_full_unsafe?
        remove_worst_connection
      end

      # Create new connection
      connection = create_connection(host, port, use_tls)
      @connections[connection_key] = connection
      @connection_metadata[connection_key] = ConnectionMetadata.new(connection)

      connection
    end

    private def create_connection(host : String, port : Int32, use_tls : Bool) : BaseConnection
      if negotiator = @protocol_negotiator
        negotiator.create_connection(host, port, use_tls, @verify_ssl)
      else
        # Fallback to HTTP/2 if no protocol negotiator is provided
        H2::Client.new(host, port, verify_ssl: @verify_ssl, use_tls: use_tls)
      end
    end

    private def remove_worst_connection : Nil
      return if @connection_metadata.empty?

      # Find connection with lowest score
      worst_key = @connection_metadata.min_by { |_, metadata| metadata.score }[0]
      remove_connection(worst_key)
    end

    private def remove_connection(connection_key : String) : Nil
      if connection = @connections[connection_key]?
        connection.close
        @connections.delete(connection_key)
        @connection_metadata.delete(connection_key)
      end
    end

    private def find_connection_key(connection : BaseConnection) : String?
      @connections.each do |key, conn|
        return key if conn == connection
      end
      nil
    end
  end
end
