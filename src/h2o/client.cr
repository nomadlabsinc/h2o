module H2O
  class Client
    property connections : ConnectionsHash
    property connection_pool_size : Int32
    property timeout : Time::Span

    def initialize(@connection_pool_size : Int32 = 10, @timeout : Time::Span = 30.seconds)
      @connections = ConnectionsHash.new
    end

    def get(url : String, headers : Headers = Headers.new) : Response?
      request("GET", url, headers)
    end

    def post(url : String, body : String? = nil, headers : Headers = Headers.new) : Response?
      request("POST", url, headers, body)
    end

    def put(url : String, body : String? = nil, headers : Headers = Headers.new) : Response?
      request("PUT", url, headers, body)
    end

    def delete(url : String, headers : Headers = Headers.new) : Response?
      request("DELETE", url, headers)
    end

    def head(url : String, headers : Headers = Headers.new) : Response?
      request("HEAD", url, headers)
    end

    def options(url : String, headers : Headers = Headers.new) : Response?
      request("OPTIONS", url, headers)
    end

    def patch(url : String, body : String? = nil, headers : Headers = Headers.new) : Response?
      request("PATCH", url, headers, body)
    end

    def request(method : String, url : String, headers : Headers = Headers.new, body : String? = nil) : Response?
      uri, host = parse_url_with_host(url)
      connection : BaseConnection = get_connection(host, uri.port || 443)
      request_path : String = build_request_path(uri)
      request_headers : Headers = prepare_headers(headers, uri)
      execute_request(connection, method, request_path, request_headers, body)
    end

    def close : Nil
      @connections.each_value(&.close)
      @connections.clear
    end

    private def parse_url_with_host(url : String) : {URI, String}
      uri = URI.parse(url)

      unless uri.scheme == "https"
        raise ArgumentError.new("Only HTTPS URLs are supported")
      end

      host = uri.host
      if !host || host.empty?
        raise ArgumentError.new("Invalid URL: missing host")
      end

      {uri, host}
    end

    private def get_connection(host : String, port : Int32) : BaseConnection
      connection_key : String = "#{host}:#{port}"
      existing_connection : BaseConnection? = find_existing_connection(connection_key)
      return existing_connection if existing_connection
      create_new_connection(connection_key, host, port)
    end

    private def cleanup_closed_connections : Nil
      @connections.reject! { |_, connection| connection.closed? }
    end

    private def create_connection_with_fallback(host : String, port : Int32) : BaseConnection?
      try_http2_connection(host, port) || try_http1_connection(host, port)
    rescue ex : Exception
      Log.error { "Connection creation failed: #{ex.message}" }
      nil
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

    private def find_existing_connection(connection_key : String) : BaseConnection?
      existing_connection : BaseConnection? = @connections[connection_key]?
      return nil if !existing_connection || existing_connection.closed?
      existing_connection
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
