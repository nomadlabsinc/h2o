module H2O
  class Client
    property connections : Hash(String, Connection)
    property connection_pool_size : Int32
    property timeout : Time::Span

    def initialize(@connection_pool_size : Int32 = 10, @timeout : Time::Span = 30.seconds)
      @connections = Hash(String, Connection).new
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
      uri = parse_url(url)
      connection = get_connection(uri.host.not_nil!, uri.port || 443)

      path = uri.path
      path = "/" if path.empty?
      path += "?" + uri.query if uri.query

      request_headers = prepare_headers(headers, uri)

      begin
        with_timeout(@timeout) do
          connection.request(method, path, request_headers, body)
        end
      rescue ex : TimeoutError
        Log.error { "Request timeout: #{ex.message}" }
        nil
      rescue ex : Exception
        Log.error { "Request failed: #{ex.message}" }
        nil
      end
    end

    def close : Nil
      @connections.each_value(&.close)
      @connections.clear
    end

    private def parse_url(url : String) : URI
      uri = URI.parse(url)

      unless uri.scheme == "https"
        raise ArgumentError.new("Only HTTPS URLs are supported")
      end

      unless uri.host
        raise ArgumentError.new("Invalid URL: missing host")
      end

      uri
    end

    private def get_connection(host : String, port : Int32) : Connection
      connection_key = "#{host}:#{port}"

      existing_connection = @connections[connection_key]?
      if existing_connection && !existing_connection.closed
        return existing_connection
      end

      cleanup_closed_connections

      if @connections.size >= @connection_pool_size
        oldest_connection = @connections.values.first?
        if oldest_connection
          oldest_connection.close
          @connections.delete(@connections.key_for(oldest_connection))
        end
      end

      connection = Connection.new(host, port)
      @connections[connection_key] = connection
      connection
    end

    private def cleanup_closed_connections : Nil
      @connections.reject! { |_, connection| connection.closed }
    end

    private def prepare_headers(headers : Headers, uri : URI) : Headers
      prepared_headers = headers.dup

      unless prepared_headers.has_key?("host")
        host_header = uri.host.not_nil!
        host_header += ":#{uri.port}" if uri.port && uri.port != 443
        prepared_headers["host"] = host_header
      end

      unless prepared_headers.has_key?("user-agent")
        prepared_headers["user-agent"] = "h2o/#{VERSION}"
      end

      unless prepared_headers.has_key?("accept")
        prepared_headers["accept"] = "*/*"
      end

      prepared_headers
    end

    private def with_timeout(timeout : Time::Span, &block : -> T) : T forall T
      start_time = Time.monotonic
      result = nil
      exception = nil

      fiber = spawn do
        begin
          result = yield
        rescue ex
          exception = ex
        end
      end

      while result.nil? && exception.nil?
        if Time.monotonic - start_time > timeout
          raise TimeoutError.new("Operation timed out after #{timeout}")
        end
        Fiber.yield
      end

      if ex = exception
        raise ex
      end

      result.not_nil!
    end
  end
end
