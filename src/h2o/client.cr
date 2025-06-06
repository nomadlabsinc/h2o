module H2O
  class Client
    property circuit_breaker_adapter : CircuitBreakerAdapter?
    property circuit_breaker_enabled : Bool
    property connection_pool_size : Int32
    property connections : ConnectionsHash
    property default_circuit_breaker : Breaker?
    property timeout : Time::Span

    def initialize(@connection_pool_size : Int32 = 10,
                   @timeout : Time::Span = H2O.config.default_timeout,
                   @circuit_breaker_enabled : Bool = H2O.config.circuit_breaker_enabled,
                   @circuit_breaker_adapter : CircuitBreakerAdapter? = nil,
                   @default_circuit_breaker : Breaker? = H2O.config.default_circuit_breaker)
      @connections = ConnectionsHash.new
      @protocol_cache = ProtocolCache.new
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
      existing_connection : BaseConnection? = find_existing_connection(connection_key)
      return existing_connection if existing_connection
      create_new_connection(connection_key, host, port)
    end

    private def cleanup_closed_connections : Nil
      @connections.reject! { |_, connection| connection.closed? }
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
      Timeout(Response?).execute(@timeout) do
        connection.request(method, path, headers, body)
      end
    rescue ex : Exception
      Log.error { "Request failed: #{ex.message}" }
      nil
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
      enforce_pool_size_limit
      connection : BaseConnection? = create_connection_with_fallback(host, port)
      raise ConnectionError.new("Connection failed") unless connection
      @connections[connection_key] = connection
      connection
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
