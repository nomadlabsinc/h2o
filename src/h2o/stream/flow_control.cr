require "../flow_control_validation"

module H2O
  class Stream
    # Stream-level flow control management
    # Handles individual stream window size and flow control validation
    class FlowControl
      DEFAULT_WINDOW_SIZE = 65535_i32

      property local_window_size : Int32
      property remote_window_size : Int32
      property initial_window_size : Int32

      def initialize(@initial_window_size : Int32 = DEFAULT_WINDOW_SIZE)
        @local_window_size = @initial_window_size
        @remote_window_size = @initial_window_size
      end

      # Update local window size from WINDOW_UPDATE frame
      def update_local_window(increment : UInt32, stream_id : StreamId) : Nil
        # Validate increment according to HTTP/2 specification
        FlowControlValidation.validate_window_update_increment(increment)
        FlowControlValidation.validate_window_size_after_update(@local_window_size, increment, stream_id)

        @local_window_size += increment.to_i32
      end

      # Update remote window size from peer WINDOW_UPDATE
      def update_remote_window(increment : UInt32, stream_id : StreamId) : Nil
        # Validate increment according to HTTP/2 specification
        FlowControlValidation.validate_window_update_increment(increment)
        FlowControlValidation.validate_window_size_after_update(@remote_window_size, increment, stream_id)

        @remote_window_size += increment.to_i32
      end

      # Consume local window space for incoming data
      def consume_local_window(size : Int32, stream_id : StreamId) : Nil
        return if size <= 0 # Empty DATA frames don't consume flow control

        FlowControlValidation.validate_data_frame_flow_control(size, @local_window_size, stream_id)
        @local_window_size -= size

        # Validate flow control state after consumption
        validate_flow_control_state(stream_id)
      end

      # Consume remote window space for outgoing data
      def consume_remote_window(size : Int32, stream_id : StreamId) : Nil
        return if size <= 0 # Empty DATA frames don't consume flow control

        FlowControlValidation.validate_data_frame_flow_control(size, @remote_window_size, stream_id)
        @remote_window_size -= size

        # Validate flow control state after consumption
        validate_flow_control_state(stream_id)
      end

      # Check if we can send data (have remote window space)
      def can_send_data?(size : Int32) : Bool
        @remote_window_size >= size
      end

      # Check if we can receive data (have local window space)
      def can_receive_data?(size : Int32) : Bool
        @local_window_size >= size
      end

      # Check if local window needs update
      def needs_window_update? : Bool
        @local_window_size <= (@initial_window_size / 2)
      end

      # Get available remote window space
      def available_remote_window : Int32
        @remote_window_size
      end

      # Get available local window space
      def available_local_window : Int32
        @local_window_size
      end

      # Create a WINDOW_UPDATE frame for this stream
      def create_window_update(increment : Int32, stream_id : StreamId) : WindowUpdateFrame
        # Validate increment before creating frame
        increment_u32 = increment.to_u32
        FlowControlValidation.validate_window_update_increment(increment_u32)
        FlowControlValidation.validate_window_size_after_update(@local_window_size, increment_u32, stream_id)

        @local_window_size += increment
        validate_flow_control_state(stream_id)

        WindowUpdateFrame.new(stream_id, increment_u32)
      end

      # Reset flow control windows to initial size
      def reset_windows : Nil
        @local_window_size = @initial_window_size
        @remote_window_size = @initial_window_size
      end

      # Update initial window size (affects future calculations)
      def update_initial_window_size(new_size : Int32, stream_id : StreamId) : Int32
        # Calculate the difference to adjust existing windows
        difference = new_size - @initial_window_size
        @initial_window_size = new_size

        # Adjust local window by the difference
        new_local_window = @local_window_size.to_i64 + difference.to_i64
        new_remote_window = @remote_window_size.to_i64 + difference.to_i64

        # Check for overflow/underflow
        if new_local_window > Int32::MAX || new_remote_window > Int32::MAX
          raise StreamError.new("Window size overflow after INITIAL_WINDOW_SIZE update", stream_id, ErrorCode::FlowControlError)
        elsif new_local_window < 0 || new_remote_window < 0
          raise StreamError.new("Window size underflow after INITIAL_WINDOW_SIZE update", stream_id, ErrorCode::FlowControlError)
        end

        @local_window_size = new_local_window.to_i32
        @remote_window_size = new_remote_window.to_i32

        validate_flow_control_state(stream_id)
        difference
      end

      # Check if flow control is available for outgoing data
      def flow_control_available? : Bool
        @remote_window_size > 0
      end

      # Check if windows are exhausted
      def local_window_exhausted? : Bool
        @local_window_size <= 0
      end

      def remote_window_exhausted? : Bool
        @remote_window_size <= 0
      end

      # Validate current flow control state
      def validate_flow_control_state(stream_id : StreamId) : Nil
        FlowControlValidation.validate_flow_control_state(@local_window_size, @remote_window_size, stream_id)
      end

      # Get flow control statistics
      def statistics : {local_window: Int32, remote_window: Int32, initial_window: Int32}
        {
          local_window:   @local_window_size,
          remote_window:  @remote_window_size,
          initial_window: @initial_window_size,
        }
      end
    end
  end
end
