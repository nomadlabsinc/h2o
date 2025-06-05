module H2O
  # Reusable timeout utility for various HTTP/2 operations
  class Timeout(T)
    # Execute a block with a timeout, returning the result or nil on timeout
    def self.execute(timeout : Time::Span, &block : -> T?) : T?
      result_channel = Channel(T?).new(1)

      spawn do
        begin
          result_channel.send(block.call)
        rescue ex : Exception
          # Exception will be handled by outer rescue block
          result_channel.send(nil)
        end
      end

      select
      when result = result_channel.receive
        result
      when timeout(timeout)
        Log.debug { "Operation timed out after #{timeout}" }
        nil
      end
    rescue ex : Exception
      Log.error { "Timeout execution failed: #{ex.message}" }
      nil
    end

    # Execute a block with timeout, raising TimeoutError on timeout
    def self.execute!(timeout : Time::Span, &block : -> T) : T
      result_channel = Channel(T).new(1)
      exception_channel = Channel(Exception).new(1)

      spawn do
        begin
          result_channel.send(block.call)
        rescue ex
          exception_channel.send(ex)
        end
      end

      select
      when result = result_channel.receive
        result
      when exception = exception_channel.receive
        raise exception
      when timeout(timeout)
        raise TimeoutError.new("Operation timed out after #{timeout}")
      end
    end

    # Execute with timeout and custom timeout handler
    def self.execute_with_handler(timeout : Time::Span, timeout_handler : -> U, &block : -> T) : T | U forall U
      result_channel = Channel(T).new(1)

      spawn do
        begin
          result_channel.send(block.call)
        rescue ex : Exception
          # Exception will be handled by outer rescue block
          # Don't send anything - let timeout occur
        end
      end

      select
      when result = result_channel.receive
        result
      when timeout(timeout)
        timeout_handler.call
      end
    rescue ex : Exception
      Log.error { "Timeout execution with handler failed: #{ex.message}" }
      timeout_handler.call
    end
  end

  # Specialized timeout error for HTTP/2 operations
  class TimeoutError < Exception
    def initialize(message : String)
      super(message)
    end
  end
end
