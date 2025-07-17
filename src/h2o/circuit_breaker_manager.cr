require "./circuit_breaker"

module H2O
  # Circuit breaker manager following SRP principles
  # Manages multiple circuit breaker instances per host/service
  class CircuitBreakerManager
    @circuit_breakers : Hash(String, Breaker)
    @enabled : Bool
    @adapter : CircuitBreakerAdapter?
    @default_breaker : Breaker?
    @failure_threshold : Int32
    @recovery_timeout : Time::Span
    @mutex : Mutex

    def initialize(@enabled : Bool = false,
                   @adapter : CircuitBreakerAdapter? = nil,
                   @default_breaker : Breaker? = nil,
                   @failure_threshold : Int32 = 5,
                   @recovery_timeout : Time::Span = 60.seconds)
      @circuit_breakers = Hash(String, Breaker).new
      @mutex = Mutex.new
    end

    # Execute a request with circuit breaker protection
    def execute(host : String, port : Int32, &block : -> Response) : Response
      return yield unless @enabled

      breaker = get_or_create_breaker(host, port)

      case breaker.state
      when .open?
        # Circuit is open - fail fast
        Response.error(503, "Circuit breaker is open for #{host}:#{port}", "HTTP/2")
      when .half_open?
        # Circuit is half-open - try one request
        execute_with_breaker(breaker, &block)
      else
        # Circuit is closed - normal execution
        execute_with_breaker(breaker, &block)
      end
    end

    # Get circuit breaker for specific host
    def get_breaker(host : String, port : Int32) : Breaker?
      @mutex.synchronize do
        breaker_key = "#{host}:#{port}"
        @circuit_breakers[breaker_key]?
      end
    end

    # Create or get existing circuit breaker
    def get_or_create_breaker(host : String, port : Int32) : Breaker
      @mutex.synchronize do
        breaker_key = "#{host}:#{port}"
        @circuit_breakers[breaker_key] ||= create_breaker(host, port)
      end
    end

    # Manually open circuit breaker for host
    def open_breaker(host : String, port : Int32) : Nil
      breaker = get_or_create_breaker(host, port)
      breaker.force_open
    end

    # Manually close circuit breaker for host
    def close_breaker(host : String, port : Int32) : Nil
      breaker = get_or_create_breaker(host, port)
      breaker.reset
    end

    # Reset circuit breaker for host
    def reset_breaker(host : String, port : Int32) : Nil
      breaker = get_or_create_breaker(host, port)
      breaker.reset
    end

    # Check if circuit breaker is open for host
    def circuit_open?(host : String, port : Int32) : Bool
      breaker = get_breaker(host, port)
      breaker ? breaker.state.open? : false
    end

    # Get all circuit breaker states
    def all_states : Hash(String, String)
      @mutex.synchronize do
        result = Hash(String, String).new
        @circuit_breakers.each do |key, breaker|
          result[key] = breaker.state.to_s
        end
        result
      end
    end

    # Get circuit breaker statistics
    def statistics : Hash(Symbol, Int32 | Float64)
      @mutex.synchronize do
        total_breakers = @circuit_breakers.size
        open_breakers = @circuit_breakers.values.count(&.state.open?)
        half_open_breakers = @circuit_breakers.values.count(&.state.half_open?)
        closed_breakers = @circuit_breakers.values.count(&.state.closed?)

        total_requests = @circuit_breakers.values.sum(&.statistics.total_requests)
        total_failures = @circuit_breakers.values.sum(&.statistics.failure_count)
        total_successes = @circuit_breakers.values.sum(&.statistics.success_count)

        {
          :total_breakers     => total_breakers,
          :open_breakers      => open_breakers,
          :half_open_breakers => half_open_breakers,
          :closed_breakers    => closed_breakers,
          :total_requests     => total_requests,
          :total_failures     => total_failures,
          :total_successes    => total_successes,
          :failure_rate       => total_requests > 0 ? total_failures.to_f64 / total_requests.to_f64 : 0.0,
          :success_rate       => total_requests > 0 ? total_successes.to_f64 / total_requests.to_f64 : 0.0,
        }
      end
    end

    # Get detailed statistics for specific host
    def host_statistics(host : String, port : Int32) : Hash(Symbol, Int32 | Float64 | String)?
      breaker = get_breaker(host, port)
      return nil unless breaker

      {
        :state         => breaker.state.to_s,
        :request_count => breaker.request_count,
        :failure_count => breaker.failure_count,
        :success_count => breaker.success_count,
        :failure_rate  => breaker.failure_rate,
        :last_failure  => breaker.last_failure_time ? breaker.last_failure_time.to_s : "never",
        :opened_at     => breaker.opened_at ? breaker.opened_at.to_s : "never",
      }
    end

    # Enable circuit breaker functionality
    def enable : Nil
      @enabled = true
    end

    # Disable circuit breaker functionality
    def disable : Nil
      @enabled = false
    end

    # Check if circuit breaker is enabled
    def enabled? : Bool
      @enabled
    end

    # Clear all circuit breakers
    def clear : Nil
      @mutex.synchronize do
        @circuit_breakers.clear
      end
    end

    # Remove circuit breaker for specific host
    def remove_breaker(host : String, port : Int32) : Nil
      @mutex.synchronize do
        breaker_key = "#{host}:#{port}"
        @circuit_breakers.delete(breaker_key)
      end
    end

    # Clean up idle circuit breakers
    def cleanup_idle_breakers(idle_timeout : Time::Span = 1.hour) : Nil
      @mutex.synchronize do
        current_time = Time.utc
        idle_keys = [] of String

        @circuit_breakers.each do |key, breaker|
          # Check last activity from statistics
          last_failure = breaker.statistics.last_failure_time
          last_success = breaker.statistics.last_success_time

          if last_failure || last_success
            last_activity = [last_failure, last_success].compact.max
            if (current_time - last_activity) > idle_timeout
              idle_keys << key
            end
          end
        end

        idle_keys.each { |key| @circuit_breakers.delete(key) }
      end
    end

    # Update configuration for all breakers
    def update_configuration(failure_threshold : Int32? = nil, recovery_timeout : Time::Span? = nil) : Nil
      @failure_threshold = failure_threshold if failure_threshold
      @recovery_timeout = recovery_timeout if recovery_timeout

      # Update existing breakers
      @mutex.synchronize do
        @circuit_breakers.each_value do |breaker|
          breaker.failure_threshold = @failure_threshold
          breaker.recovery_timeout = @recovery_timeout
        end
      end
    end

    private def create_breaker(host : String, port : Int32) : Breaker
      # Use provided default breaker or create new one
      if default = @default_breaker
        Breaker.new(
          "#{host}:#{port}",
          failure_threshold: default.failure_threshold,
          recovery_timeout: default.recovery_timeout
        )
      else
        Breaker.new(
          "#{host}:#{port}",
          failure_threshold: @failure_threshold,
          recovery_timeout: @recovery_timeout
        )
      end
    end

    private def execute_with_breaker(breaker : Breaker, &block : -> Response) : Response
      # Use the breaker's built-in execute method
      breaker.execute("", H2O::Headers.new) do
        block.call
      end
    end
  end
end
