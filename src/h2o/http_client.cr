require "./connection_pool"
require "./protocol_negotiator"
require "./circuit_breaker_manager"
require "./request_translator"
require "./response_translator"

module H2O
  # Coordinates connection pooling, protocol negotiation, and circuit breaking
  # Prevents any single component from accumulating multiple responsibilities
  class HttpClient
    @connection_pool : ConnectionPool
    @protocol_negotiator : ProtocolNegotiator
    @circuit_breaker_manager : CircuitBreakerManager
    @timeout : Time::Span
    @closed : Bool = false

    def initialize(connection_pool_size : Int32 = 10,
                   h2_prior_knowledge : Bool = false,
                   timeout : Time::Span = H2O.config.default_timeout,
                   verify_ssl : Bool = H2O.config.verify_ssl,
                   circuit_breaker_enabled : Bool = H2O.config.circuit_breaker_enabled,
                   circuit_breaker_adapter : CircuitBreakerAdapter? = nil,
                   default_circuit_breaker : Breaker? = H2O.config.default_circuit_breaker)
      @protocol_negotiator = ProtocolNegotiator.new(h2_prior_knowledge)
      @connection_pool = ConnectionPool.new(connection_pool_size, verify_ssl, @protocol_negotiator)
      @circuit_breaker_manager = CircuitBreakerManager.new(
        circuit_breaker_enabled,
        circuit_breaker_adapter,
        default_circuit_breaker
      )
      @timeout = timeout
    end

    def get(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("GET", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def post(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("POST", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def put(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("PUT", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def delete(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("DELETE", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def head(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("HEAD", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def options(url : String, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("OPTIONS", url, headers, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def patch(url : String, body : String? = nil, headers : Headers = Headers.new, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      request("PATCH", url, headers, body, bypass_circuit_breaker: bypass_circuit_breaker, circuit_breaker: circuit_breaker)
    end

    def request(method : String, url : String, headers : Headers = Headers.new, body : String? = nil, *, bypass_circuit_breaker : Bool = false, circuit_breaker : Bool? = nil) : Response
      raise ConnectionError.new("Client has been closed") if @closed

      uri = URI.parse(url)
      host = uri.host || raise ArgumentError.new("Invalid URL: missing host")
      port = uri.port || (uri.scheme == "https" ? 443 : 80)
      use_tls = uri.scheme == "https"
      use_circuit_breaker = should_use_circuit_breaker?(bypass_circuit_breaker, circuit_breaker)

      begin
        if use_circuit_breaker
          execute_with_circuit_breaker(host, port, method, uri, headers, body, use_tls)
        else
          execute_without_circuit_breaker(host, port, method, uri, headers, body, use_tls)
        end
      rescue ex : ArgumentError
        raise ex
      rescue ex : TimeoutError | ConnectionError
        Log.error { "Request failed for #{method} #{url}: #{ex.message}" }
        Response.error(0, ex.message.to_s, "HTTP/2")
      rescue ex : Exception
        Log.error { "Unexpected error for #{method} #{url}: #{ex.message}" }
        Response.error(0, ex.message.to_s, "HTTP/2")
      end
    end

    def close : Nil
      @closed = true
      @connection_pool.close
      @protocol_negotiator.clear_cache
      @circuit_breaker_manager.clear
    end

    def warmup_connection(host : String, port : Int32 = 443) : Nil
      @connection_pool.warmup_connection(host, port)
    end

    def set_batch_processing(enabled : Bool) : Nil
      @connection_pool.set_batch_processing(enabled)
    end

    def statistics : Hash(Symbol, Hash(Symbol, Int32 | Float64))
      {
        :connection_pool     => @connection_pool.statistics,
        :protocol_negotiator => @protocol_negotiator.statistics,
        :circuit_breaker     => @circuit_breaker_manager.statistics,
      }
    end

    def force_protocol(host : String, port : Int32, protocol : String) : Nil
      @protocol_negotiator.force_protocol(host, port, protocol)
    end

    def open_circuit_breaker(host : String, port : Int32) : Nil
      @circuit_breaker_manager.open_breaker(host, port)
    end

    def close_circuit_breaker(host : String, port : Int32) : Nil
      @circuit_breaker_manager.close_breaker(host, port)
    end

    def circuit_breaker_state(host : String, port : Int32) : String?
      breaker = @circuit_breaker_manager.get_breaker(host, port)
      breaker ? breaker.state.to_s : nil
    end

    def cleanup_expired_connections : Nil
      @connection_pool.cleanup_expired_connections
    end

    def cleanup_expired_cache : Nil
      @protocol_negotiator.cleanup_expired_cache
      @circuit_breaker_manager.cleanup_idle_breakers
    end

    private def should_use_circuit_breaker?(bypass : Bool, circuit_breaker : Bool?) : Bool
      return false if bypass
      return circuit_breaker if circuit_breaker.is_a?(Bool)
      @circuit_breaker_manager.enabled?
    end

    private def execute_with_circuit_breaker(host : String, port : Int32, method : String, uri : URI, headers : Headers, body : String?, use_tls : Bool) : Response
      @circuit_breaker_manager.execute(host, port) do
        perform_request(host, port, method, uri, headers, body, use_tls)
      end
    end

    private def execute_without_circuit_breaker(host : String, port : Int32, method : String, uri : URI, headers : Headers, body : String?, use_tls : Bool) : Response
      perform_request(host, port, method, uri, headers, body, use_tls)
    end

    private def perform_request(host : String, port : Int32, method : String, uri : URI, headers : Headers, body : String?, use_tls : Bool) : Response
      start_time = Time.utc

      connection = @connection_pool.get_connection(host, port, use_tls)

      begin
        response = case connection
                   when H2::Client
                     perform_h2_request(connection, method, uri, headers, body)
                   when H1::Client
                     perform_h1_request(connection, method, uri, headers, body)
                   else
                     raise ConnectionError.new("Unknown connection type: #{connection.class}")
                   end

        response_time = Time.utc - start_time
        @connection_pool.return_connection(connection, response.success?, response_time)
        response
      rescue ex
        response_time = Time.utc - start_time
        @connection_pool.return_connection(connection, false, response_time)
        raise ex
      end
    end

    private def perform_h2_request(connection : H2::Client, method : String, uri : URI, headers : Headers, body : String?) : Response
      connection.request(method, uri.path || "/", headers, body)
    end

    private def perform_h1_request(connection : H1::Client, method : String, uri : URI, headers : Headers, body : String?) : Response
      connection.request(method, uri.path || "/", headers, body)
    end
  end
end
