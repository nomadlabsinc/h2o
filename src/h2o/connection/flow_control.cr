require "../flow_control_validation"

module H2O
  class Connection
    # Connection-level flow control management
    # Handles connection window size and flow control validation
    class FlowControl
      DEFAULT_WINDOW_SIZE = 65535_i32

      property window_size : Int32
      property initial_window_size : Int32

      def initialize(@initial_window_size : Int32 = DEFAULT_WINDOW_SIZE)
        @window_size = @initial_window_size
      end

      # Update window size from WINDOW_UPDATE frame
      def update_window(increment : UInt32) : Nil
        # Validate increment according to HTTP/2 specification
        if increment == 0
          raise ConnectionError.new("WINDOW_UPDATE increment cannot be 0", ErrorCode::ProtocolError)
        end

        # Check for overflow
        new_window = @window_size.to_i64 + increment.to_i64
        if new_window > Int32::MAX
          raise ConnectionError.new("Connection window size overflow", ErrorCode::FlowControlError)
        end

        @window_size = new_window.to_i32
      end

      # Consume window space for outgoing data
      def consume_window(size : Int32) : Nil
        if size > @window_size
          raise ConnectionError.new("Insufficient connection window: #{size} > #{@window_size}", ErrorCode::FlowControlError)
        end

        @window_size -= size
      end

      # Check if we have enough window space
      def can_send?(size : Int32) : Bool
        @window_size >= size
      end

      # Reset window size to initial value
      def reset_window : Nil
        @window_size = @initial_window_size
      end

      # Update initial window size (affects future streams)
      def update_initial_window_size(new_size : Int32) : Int32
        # Calculate the difference to adjust existing window
        difference = new_size - @initial_window_size
        @initial_window_size = new_size

        # Adjust current window by the difference
        new_window = @window_size.to_i64 + difference.to_i64

        # Check for overflow/underflow
        if new_window > Int32::MAX
          raise ConnectionError.new("Window size overflow after INITIAL_WINDOW_SIZE update", ErrorCode::FlowControlError)
        elsif new_window < 0
          raise ConnectionError.new("Window size underflow after INITIAL_WINDOW_SIZE update", ErrorCode::FlowControlError)
        end

        @window_size = new_window.to_i32
        difference
      end

      # Get current window size
      def current_window : Int32
        @window_size
      end

      # Check if window is exhausted
      def window_exhausted? : Bool
        @window_size <= 0
      end

      # Validate current window state
      def validate : Nil
        if @window_size < 0
          raise ConnectionError.new("Negative connection window size: #{@window_size}", ErrorCode::FlowControlError)
        end
      end
    end
  end
end
