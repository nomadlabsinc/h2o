module H2O
  # Comprehensive error handling utilities
  # Provides consistent error handling patterns across the codebase
  module ErrorHandling
    # Standard error categories for consistent handling
    enum ErrorCategory
      Network
      Protocol
      Security
      Resource
      Timeout
      Configuration
      Internal
    end

    # Enhanced error handling with categorization and retry logic
    class ErrorHandler
      property max_retries : Int32
      property retry_delays : Array(Time::Span)
      property circuit_breaker : CircuitBreakerManager?

      def initialize(@max_retries : Int32 = 3, @circuit_breaker : CircuitBreakerManager? = nil)
        @retry_delays = [
          100.milliseconds,
          500.milliseconds,
          1.second,
          2.seconds,
          5.seconds,
        ]
      end

      # Execute operation with comprehensive error handling and retry logic
      def execute(operation_name : String, &) : T forall T
        retries = 0
        last_error : Exception? = nil

        loop do
          begin
            # Use circuit breaker if available
            if cb = @circuit_breaker
              return cb.execute(operation_name) { yield }
            else
              return yield
            end
          rescue ex : IO::TimeoutError
            last_error = ex
            category = ErrorCategory::Timeout
            Log.warn { "Timeout in #{operation_name} (attempt #{retries + 1}): #{ex.message}" }
          rescue ex : IO::Error
            last_error = ex
            category = ErrorCategory::Network
            Log.warn { "Network error in #{operation_name} (attempt #{retries + 1}): #{ex.message}" }
          rescue ex : Socket::Error
            last_error = ex
            category = ErrorCategory::Network
            Log.warn { "Socket error in #{operation_name} (attempt #{retries + 1}): #{ex.message}" }
          rescue ex : OpenSSL::Error
            last_error = ex
            category = ErrorCategory::Security
            Log.warn { "SSL error in #{operation_name} (attempt #{retries + 1}): #{ex.message}" }
          rescue ex : H2O::ProtocolError
            last_error = ex
            category = ErrorCategory::Protocol
            Log.error { "Protocol error in #{operation_name}: #{ex.message}" }
            # Protocol errors are not retryable
            raise ex
          rescue ex : H2O::ConnectionError
            last_error = ex
            category = ErrorCategory::Resource
            Log.warn { "Connection error in #{operation_name} (attempt #{retries + 1}): #{ex.message}" }
          rescue ex : ArgumentError
            last_error = ex
            category = ErrorCategory::Configuration
            Log.error { "Configuration error in #{operation_name}: #{ex.message}" }
            # Configuration errors are not retryable
            raise ex
          rescue ex
            last_error = ex
            category = ErrorCategory::Internal
            Log.error { "Unexpected error in #{operation_name}: #{ex.class}: #{ex.message}" }
            # Unknown errors are not retryable to avoid infinite loops
            raise ex
          end

          # Check if we should retry
          retries += 1
          if retries >= @max_retries || !retryable_error?(category)
            Log.error { "Max retries exceeded for #{operation_name}, giving up after #{retries} attempts" }
            raise last_error.not_nil!
          end

          # Wait before retry with exponential backoff
          delay = retry_delay(retries)
          Log.info { "Retrying #{operation_name} in #{delay.total_milliseconds}ms (attempt #{retries + 1})" }
          sleep(delay)
        end
      end

      # Check if an error category is retryable
      private def retryable_error?(category : ErrorCategory) : Bool
        case category
        when .network?, .timeout?, .resource?
          true
        else
          false
        end
      end

      # Calculate retry delay with exponential backoff
      private def retry_delay(attempt : Int32) : Time::Span
        return @retry_delays.last if attempt > @retry_delays.size
        @retry_delays[attempt - 1]
      end
    end

    # Utility methods for consistent error handling patterns
    module Utils
      # Safe resource cleanup that doesn't throw exceptions
      def self.safe_cleanup(resource, method_name : String = "close") : Nil
        case method_name
        when "close"
          resource.close if resource.responds_to?(:close)
        when "finalize"
          resource.finalize if resource.responds_to?(:finalize)
        else
          # For other methods, attempt the call directly
          resource.try(&.close) if method_name == "close"
        end
      rescue ex
        Log.warn { "Error during #{method_name} cleanup: #{ex.message}" }
      end

      # Execute block with automatic resource cleanup
      def self.with_cleanup(resource, cleanup_method : String = "close", &)
        yield
      ensure
        safe_cleanup(resource, cleanup_method)
      end

      # Validate arguments with descriptive error messages
      def self.validate_argument(condition : Bool, message : String) : Nil
        unless condition
          raise ArgumentError.new(message)
        end
      end

      # Safe type conversion with error handling
      def self.safe_convert(value, target_type : T.class, default : T) : T forall T
        value.as(T)
      rescue
        Log.warn { "Failed to convert #{value} to #{target_type}, using default: #{default}" }
        default
      end
    end
  end
end
