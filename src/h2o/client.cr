module H2O
  # Type aliases for cleaner code
  alias ConnectionMetadataHash = Hash(String, ConnectionMetadata)
  alias HostSet = Set(String)
  alias ConnectionHash = Hash(String, BaseConnection)

  # Enhanced connection metadata for scoring and lifecycle management
  private struct ConnectionMetadata
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

      # Bonus for recent usage (up to +20 points)
      age_bonus = Math.max(0.0, 20.0 - (Time.utc - @last_used).total_minutes)

      @score = base_score - error_penalty - speed_penalty + age_bonus
    end

    def age : Time::Span
      Time.utc - @created_at
    end

    def idle_time : Time::Span
      Time.utc - @last_used
    end
  end

  class Client
    property circuit_breaker_adapter : CircuitBreakerAdapter?
    property circuit_breaker_enabled : Bool
    property connection_pool_size : Int32
    property connections : ConnectionsHash
    property default_circuit_breaker : Breaker?
    property timeout : Time::Span

    # Enhanced connection management
    @connection_metadata : ConnectionMetadataHash
    @warmup_hosts : HostSet

    def initialize(@connection_pool_size : Int32 = 10,
                   @timeout : Time::Span = H2O.config.default_timeout,
                   @circuit_breaker_enabled : Bool = H2O.config.circuit_breaker_enabled,
                   @circuit_breaker_adapter : CircuitBreakerAdapter? = nil,
                   @default_circuit_breaker : Breaker? = H2O.config.default_circuit_breaker)
      @connections = ConnectionsHash.new
      @protocol_cache = ProtocolCache.new
      @connection_metadata = ConnectionMetadataHash.new
      @warmup_hosts = HostSet.new
    end

    def get(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("GET", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def post(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("POST", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def put(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("PUT", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def delete(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("DELETE", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def head(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("HEAD", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def options(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("OPTIONS", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def patch(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      request("PATCH", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def request(method : String, url : String, headers : Headers = Headers.new, body : String? = nil, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response?
      # Determine if circuit breaker should be used
      use_circuit_breaker = should_use_circuit_breaker?(bypass_circuit_breaker, circuit_breaker)

      if use_circuit_breaker
        execute_with_circuit_breaker(method, url, headers, body)
      else
        execute_without_circuit_breaker(method, url, headers, body)
      end
    end

    def close : Nil
      @connections.each_value(&.close)
      @connections.clear
      @connection_metadata.clear
      @warmup_hosts.clear
    end

    def set_batch_processing(enabled : Bool) : Nil
      @connections.each_value do |connection|
        if connection.is_a?(H2::Client)
          connection.set_batch_processing(enabled)
        end
      end
    end

    # Pre-warm connection to frequently used hosts
    def warmup_connection(host : String, port : Int32 = 443) : Nil
      return if @warmup_hosts.includes?(host)

      spawn do
        begin
          connection_key = String.build do |key|
            key << host << ':' << port
          end

          connection = create_connection_with_fallback(host, port)
          if connection
            @connections[connection_key] = connection
            @connection_metadata[connection_key] = ConnectionMetadata.new(connection)
            @warmup_hosts.add(host)
            Log.debug { "Warmed up connection to #{host}:#{port}" }
          end
        rescue ex
          Log.warn { "Connection warmup failed for #{host}:#{port}: #{ex.message}" }
        end
      end
    end

    private def parse_url_with_host(url : String) : UrlParseResult
      uri : URI = URI.parse(url)

      unless uri.scheme == "https"
        raise ArgumentError.new("Only HTTPS URLs are supported")
      end

      host : String? = uri.host
      if !host || host.empty?
        raise ArgumentError.new("Invalid URL: missing host")
      end

      {uri, host}
    end

    private def get_connection(host : String, port : Int32) : BaseConnection
      connection_key : ConnectionKey = String.build do |key|
        key << host << ':' << port
      end

      # Try to find the best existing connection using scoring
      best_connection = find_best_connection(connection_key)
      return best_connection if best_connection

      create_new_connection(connection_key, host, port)
    end

    private def cleanup_closed_connections : Nil
      @connections.reject! do |key, connection|
        if connection.closed?
          @connection_metadata.delete(key)
          true
        else
          false
        end
      end
    end

    # Find the best connection based on scoring algorithm
    private def find_best_connection(connection_key : String) : BaseConnection?
      connection = @connections[connection_key]?
      return nil unless connection

      metadata = @connection_metadata[connection_key]?
      return nil unless metadata

      return nil unless connection_healthy_enhanced?(connection, metadata)

      connection
    end

    # Enhanced connection health validation with scoring
    private def connection_healthy_enhanced?(connection : BaseConnection, metadata : ConnectionMetadata) : Bool
      return false if connection.closed?

      # Check basic health
      healthy = case connection
                when H2::Client
                  connection_healthy_http2?(connection)
                when H1::Client
                  connection_healthy_http1?(connection)
                else
                  false
                end

      return false unless healthy

      # Check if connection is too old or has too many errors
      return false if metadata.age > 1.hour
      return false if metadata.score < 30.0
      return false if metadata.idle_time > 5.minutes

      true
    end

    private def create_connection_with_fallback(host : String, port : Int32) : ConnectionResult
      @protocol_cache.cleanup_expired

      if preferred : ProtocolResult = @protocol_cache.get_preferred_protocol(host, port)
        case preferred
        when .http2?
          return try_http2_connection(host, port) || try_http1_connection_with_cache(host, port)
        when .http11?
          return try_http1_connection(host, port)
        end
      end

      # No cache entry, try HTTP/2 first then fallback
      if connection = try_http2_connection(host, port)
        @protocol_cache.cache_protocol(host, port, ProtocolVersion::Http2)
        connection
      elsif connection = try_http1_connection(host, port)
        @protocol_cache.cache_protocol(host, port, ProtocolVersion::Http11)
        connection
      else
        nil
      end
    rescue ex : Exception
      Log.error { "Connection creation failed: #{ex.message}" }
      nil
    end

    private def try_http1_connection_with_cache(host : String, port : Int32) : ConnectionResult
      if connection = try_http1_connection(host, port)
        @protocol_cache.cache_protocol(host, port, ProtocolVersion::Http11)
        connection
      else
        nil
      end
    end

    private def build_request_path(uri : URI) : String
      path : String = uri.path
      path = "/" if path.empty?
      query : String? = uri.query
      query ? "#{path}?#{query}" : path
    end

    private def execute_request(connection : BaseConnection, method : String, path : String, headers : Headers, body : String?) : Response?
      start_time = Time.monotonic

      begin
        result = Timeout(Response?).execute(@timeout) do
          connection.request(method, path, headers, body)
        end

        # Track performance metrics
        end_time = Time.monotonic
        response_time = end_time - start_time
        success = result.nil? ? false : true
        update_connection_metrics(connection, response_time, success)

        result
      rescue ex : Exception
        # Track failed request
        end_time = Time.monotonic
        response_time = end_time - start_time
        update_connection_metrics(connection, response_time, false)

        Log.error { "Request failed: #{ex.message}" }
        nil
      end
    end

    private def update_connection_metrics(connection : BaseConnection, response_time : Time::Span, success : Bool) : Nil
      # Find the connection key and metadata
      @connections.each do |key, conn|
        if conn == connection
          metadata = @connection_metadata[key]?
          metadata.try(&.update_usage(success, response_time))
          break
        end
      end
    end

    private def execute_with_circuit_breaker(method : String, url : String, headers : Headers, body : String?) : CircuitBreakerResult
      breaker : Breaker? = get_circuit_breaker_for_request(url)
      return nil unless breaker

      if adapter = @circuit_breaker_adapter
        return nil unless adapter.should_allow_request?
        return nil unless adapter.before_request(url, headers)
      end

      breaker.execute(url, headers) do
        execute_without_circuit_breaker(method, url, headers, body)
      end
    end

    private def execute_without_circuit_breaker(method : String, url : String, headers : Headers, body : String?) : CircuitBreakerResult
      uri, host = parse_url_with_host(url)
      connection : BaseConnection = get_connection(host, uri.port || 443)
      request_path : String = build_request_path(uri)
      request_headers : Headers = prepare_headers(headers, uri)
      execute_request(connection, method, request_path, request_headers, body)
    rescue ex : Exception
      Log.error { "Request failed without circuit breaker: #{ex.message}" }
      nil
    end

    private def get_circuit_breaker_for_request(url : String) : Breaker?
      if breaker = @default_circuit_breaker
        breaker
      else
        uri = URI.parse(url)
        host = uri.host
        return nil unless host
        create_default_circuit_breaker_for_host(host)
      end
    end

    private def create_default_circuit_breaker_for_host(host : String) : Breaker
      Breaker.new(
        name: "h2o_client_#{host}",
        failure_threshold: H2O.config.default_failure_threshold,
        recovery_timeout: H2O.config.default_recovery_timeout,
        timeout: @timeout
      )
    end

    private def should_use_circuit_breaker?(bypass : Bool, circuit_breaker_override : Bool?) : Bool
      return false if bypass
      if override = circuit_breaker_override
        return override
      end
      @circuit_breaker_enabled
    end

    private def find_existing_connection(connection_key : ConnectionKey) : BaseConnection?
      existing_connection : BaseConnection? = @connections[connection_key]?
      return nil if !existing_connection || existing_connection.closed?
      return nil unless connection_healthy?(existing_connection)
      existing_connection
    end

    private def connection_healthy?(connection : BaseConnection) : Bool
      case connection
      when H2::Client
        connection_healthy_http2?(connection)
      when H1::Client
        connection_healthy_http1?(connection)
      else
        false
      end
    end

    private def connection_healthy_http2?(connection : H2::Client) : Bool
      return false if connection.closed?
      return false if connection.closing
      return false unless connection_has_stream_capacity?(connection)
      true
    end

    private def connection_healthy_http1?(connection : H1::Client) : Bool
      !connection.closed?
    end

    private def connection_has_stream_capacity?(connection : H2::Client) : Bool
      max_streams = connection.remote_settings.max_concurrent_streams
      return true unless max_streams

      active_stream_count = connection.stream_pool.stream_count
      active_stream_count < max_streams
    end

    private def create_new_connection(connection_key : String, host : String, port : Int32) : BaseConnection
      cleanup_closed_connections
      enforce_pool_size_limit_enhanced
      connection : BaseConnection? = create_connection_with_fallback(host, port)
      raise ConnectionError.new("Connection failed") unless connection

      @connections[connection_key] = connection
      @connection_metadata[connection_key] = ConnectionMetadata.new(connection)

      connection
    end

    # Enhanced pool size enforcement with connection scoring
    private def enforce_pool_size_limit_enhanced : Nil
      return unless @connections.size >= @connection_pool_size

      # Find the worst connection to evict based on score
      worst_key = find_worst_connection_key
      if worst_key
        worst_connection = @connections[worst_key]?
        if worst_connection
          worst_connection.close
          @connections.delete(worst_key)
          @connection_metadata.delete(worst_key)
        end
      else
        # Fallback to removing the oldest connection
        enforce_pool_size_limit
      end
    end

    private def find_worst_connection_key : String?
      worst_key = nil
      worst_score = Float64::MAX

      @connection_metadata.each do |key, metadata|
        if metadata.score < worst_score
          worst_score = metadata.score
          worst_key = key
        end
      end

      worst_key
    end

    private def enforce_pool_size_limit : Nil
      return unless @connections.size >= @connection_pool_size
      oldest_connection : BaseConnection? = @connections.values.first?
      return unless oldest_connection
      oldest_connection.close
      @connections.delete(@connections.key_for(oldest_connection))
    end

    private def try_http2_connection(host : String, port : Int32) : BaseConnection?
      connection : H2::Client = H2::Client.new(host, port, connect_timeout: @timeout)
      Log.debug { "Using HTTP/2 for #{host}:#{port}" }
      connection
    rescue ConnectionError
      Log.debug { "HTTP/2 not available for #{host}:#{port}, falling back to HTTP/1.1" }
      nil
    end

    private def try_http1_connection(host : String, port : Int32) : BaseConnection?
      verify_ssl : Bool = !(host == "localhost" || host == "127.0.0.1")
      connection : H1::Client = H1::Client.new(host, port, connect_timeout: @timeout, verify_ssl: verify_ssl)
      Log.debug { "Using HTTP/1.1 for #{host}:#{port}" }
      connection
    end

    private def prepare_headers(headers : Headers, uri : URI) : Headers
      prepared_headers : Headers = headers.dup
      add_host_header(prepared_headers, uri)
      add_user_agent_header(prepared_headers)
      add_accept_header(prepared_headers)
      prepared_headers
    end

    private def add_host_header(headers : Headers, uri : URI) : Nil
      return if headers.has_key?("host")
      host : String? = uri.host
      return unless host
      host_header : String = build_host_header(host, uri.port)
      headers["host"] = host_header
    end

    private def build_host_header(host : String, port : Int32?) : String
      return host unless port && port != 443
      "#{host}:#{port}"
    end

    private def add_user_agent_header(headers : Headers) : Nil
      return if headers.has_key?("user-agent")
      headers["user-agent"] = "h2o/#{VERSION}"
    end

    private def add_accept_header(headers : Headers) : Nil
      return if headers.has_key?("accept")
      headers["accept"] = "*/*"
    end
  end
end
