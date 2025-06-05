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
      uri = parse_url(url)
      host = uri.host.not_nil!

      connection = get_connection(host, uri.port || 443)

      path = uri.path
      path = "/" if path.empty?
      if query = uri.query
        path += "?" + query
      end

      request_headers = prepare_headers(headers, uri)

      begin
        Timeout(Response?).execute(@timeout) do
          connection.request(method, path, request_headers, body)
        end
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

      host = uri.host
      if !host || host.empty?
        raise ArgumentError.new("Invalid URL: missing host")
      end

      uri
    end

    private def get_connection(host : String, port : Int32) : Connection
      connection_key : String = "#{host}:#{port}"

      existing_connection : Connection? = @connections[connection_key]?
      if existing_connection && !existing_connection.closed?
        return existing_connection
      end

      cleanup_closed_connections

      if @connections.size >= @connection_pool_size
        oldest_connection : Connection? = @connections.values.first?
        if oldest_connection
          oldest_connection.close
          @connections.delete(@connections.key_for(oldest_connection))
        end
      end

      connection : Connection? = Timeout(Connection?).execute(@timeout) do
        Connection.new(host, port, connect_timeout: @timeout)
      end

      raise ConnectionError.new("Connection timeout") unless connection

      @connections[connection_key] = connection
      connection
    end

    private def cleanup_closed_connections : Nil
      @connections.reject! { |_, connection| connection.closed? }
    end

    private def prepare_headers(headers : Headers, uri : URI) : Headers
      prepared_headers = headers.dup

      unless prepared_headers.has_key?("host")
        if host = uri.host
          host_header = host
          host_header += ":#{uri.port}" if uri.port && uri.port != 443
          prepared_headers["host"] = host_header
        end
      end

      unless prepared_headers.has_key?("user-agent")
        prepared_headers["user-agent"] = "h2o/#{VERSION}"
      end

      unless prepared_headers.has_key?("accept")
        prepared_headers["accept"] = "*/*"
      end

      prepared_headers
    end
  end
end
