module H2O
  module H2
    # Optimized HTTP/2 client with advanced performance features
    # Builds upon the base H2::Client with additional optimizations
    class OptimizedClient < Client
      # Enhanced connection pooling with circuit breakers
      property circuit_breaker : CircuitBreakerManager?

      # Performance monitoring
      property performance_stats : Hash(String, Float64)

      def initialize(
        uri : URI,
        tls_context : OpenSSL::SSL::Context::Client? = nil,
        request_timeout : Time::Span? = 30.seconds,
        connect_timeout : Time::Span? = 10.seconds,
        enable_circuit_breaker : Bool = true,
      )
        super(uri, tls_context, request_timeout, connect_timeout)

        @performance_stats = Hash(String, Float64).new

        # Initialize circuit breaker for fault tolerance
        if enable_circuit_breaker
          @circuit_breaker = CircuitBreakerManager.new
        end
      end

      # Enhanced request method with circuit breaker protection
      def request(method : String, path : String, headers : HTTP::Headers? = nil, body : String | Bytes | IO | Nil = nil) : HTTP::Client::Response
        start_time = Time.monotonic

        # Circuit breaker protection
        if cb = @circuit_breaker
          return cb.execute("http_request") do
            super(method, path, headers, body)
          end
        else
          response = super(method, path, headers, body)
        end

        # Track performance metrics
        request_time = (Time.monotonic - start_time).total_milliseconds
        @performance_stats["last_request_time"] = request_time
        @performance_stats["total_requests"] = (@performance_stats["total_requests"]? || 0.0) + 1.0

        response
      end

      # Enhanced connection management with health checking
      def ensure_connection : Nil
        # Perform connection health check before reusing
        if @socket && connection_healthy?
          return
        end

        # Fall back to normal connection establishment
        super
      end

      # Check if the current connection is healthy
      private def connection_healthy? : Bool
        return false unless @socket

        # Basic socket health check
        begin
          # Try to peek at the socket to see if it's still readable
          if @socket.responds_to?(:peek)
            @socket.peek(1)
          end
          true
        rescue
          false
        end
      end

      # Get performance statistics
      def stats : Hash(String, Float64)
        @performance_stats.dup
      end

      # Reset performance statistics
      def reset_stats : Nil
        @performance_stats.clear
      end

      # Enhanced close with circuit breaker cleanup
      def close : Nil
        @circuit_breaker.try(&.clear)
        super
      end
    end
  end
end
