module H2O
  # Strict flow control validation following Go net/http2 and Rust h2 patterns
  # Based on RFC 7540 Section 6.9 and flow control security best practices
  module FlowControlValidation
    # RFC 7540 Section 6.9.1: Initial window size limits
    INITIAL_WINDOW_SIZE =      65535
    MAX_WINDOW_SIZE     = 0x7fffffff # 2^31 - 1

    # Flow control attack prevention
    MIN_WINDOW_UPDATE_INCREMENT = 1
    MAX_WINDOW_UPDATE_INCREMENT = MAX_WINDOW_SIZE

    # Window exhaustion prevention
    WINDOW_UPDATE_THRESHOLD =   0.5 # Update when 50% consumed
    MIN_WINDOW_UPDATE_SIZE  = 32768 # 32KB minimum updates

    # Validate WINDOW_UPDATE frame increment
    def self.validate_window_update_increment(increment : UInt32) : Nil
      if increment == 0
        raise ConnectionError.new("WINDOW_UPDATE with zero increment", ErrorCode::ProtocolError)
      end

      if increment > MAX_WINDOW_UPDATE_INCREMENT
        raise ConnectionError.new("WINDOW_UPDATE increment too large: #{increment}", ErrorCode::FlowControlError)
      end
    end

    # Validate window size after update to prevent overflow
    def self.validate_window_size_after_update(current_size : Int32, increment : UInt32, stream_id : StreamId) : Nil
      new_size = current_size.to_i64 + increment.to_i64

      if new_size > MAX_WINDOW_SIZE
        if stream_id == 0
          raise ConnectionError.new("Connection window size overflow: #{new_size}", ErrorCode::FlowControlError)
        else
          raise StreamError.new("Stream window size overflow: #{new_size}", stream_id, ErrorCode::FlowControlError)
        end
      end
    end

    # Validate DATA frame against flow control window
    def self.validate_data_frame_flow_control(data_size : Int32, available_window : Int32, stream_id : StreamId) : Nil
      if data_size < 0
        raise StreamError.new("Negative data size: #{data_size}", stream_id, ErrorCode::InternalError)
      end

      if data_size > available_window
        raise StreamError.new("DATA frame exceeds flow control window: #{data_size} > #{available_window}", stream_id, ErrorCode::FlowControlError)
      end

      # RFC 7540: Empty DATA frames don't consume flow control
      # (this is handled by caller checking data_size > 0)
    end

    # Validate connection-level flow control
    def self.validate_connection_flow_control(data_size : Int32, connection_window : Int32) : Nil
      if data_size > connection_window
        raise ConnectionError.new("DATA frame exceeds connection flow control window: #{data_size} > #{connection_window}", ErrorCode::FlowControlError)
      end
    end

    # Validate SETTINGS_INITIAL_WINDOW_SIZE parameter
    def self.validate_initial_window_size_setting(value : UInt32) : Nil
      if value > MAX_WINDOW_SIZE
        raise ConnectionError.new("SETTINGS_INITIAL_WINDOW_SIZE exceeds maximum: #{value}", ErrorCode::FlowControlError)
      end
    end

    # Calculate optimal window update size
    def self.calculate_window_update_size(current_window : Int32, consumed_bytes : Int32, max_window : Int32) : UInt32?
      # Don't update if window is still reasonably large
      threshold = (max_window * WINDOW_UPDATE_THRESHOLD).to_i32
      return nil if current_window > threshold

      # Calculate how much to restore
      needed = max_window - current_window

      # Ensure minimum update size to prevent chatty updates
      update_size = Math.max(needed, MIN_WINDOW_UPDATE_SIZE)

      # Don't exceed maximum window size
      max_increment = MAX_WINDOW_SIZE - current_window
      update_size = Math.min(update_size, max_increment)

      return nil if update_size <= 0

      update_size.to_u32
    end

    # Validate flow control state consistency
    def self.validate_flow_control_state(local_window : Int32, remote_window : Int32, stream_id : StreamId) : Nil
      if local_window < 0
        raise StreamError.new("Local window size is negative: #{local_window}", stream_id, ErrorCode::InternalError)
      end

      if remote_window < 0
        raise StreamError.new("Remote window size is negative: #{remote_window}", stream_id, ErrorCode::InternalError)
      end

      if local_window > MAX_WINDOW_SIZE
        raise StreamError.new("Local window size exceeds maximum: #{local_window}", stream_id, ErrorCode::FlowControlError)
      end

      if remote_window > MAX_WINDOW_SIZE
        raise StreamError.new("Remote window size exceeds maximum: #{remote_window}", stream_id, ErrorCode::FlowControlError)
      end
    end

    # Detect potential flow control attacks
    def self.detect_flow_control_attack(window_updates_count : Int32, time_window : Time::Span, threshold : Int32 = 100) : Nil
      # Detect excessive window updates (potential DoS)
      if window_updates_count > threshold
        raise ConnectionError.new("Excessive WINDOW_UPDATE frames: #{window_updates_count} in #{time_window}", ErrorCode::EnhanceYourCalm)
      end
    end

    # Validate window update timing to prevent slow-drip attacks
    def self.validate_window_update_timing(last_update : Time, min_interval : Time::Span = 10.milliseconds) : Nil
      if Time.utc - last_update < min_interval
        raise ConnectionError.new("WINDOW_UPDATE frames too frequent", ErrorCode::EnhanceYourCalm)
      end
    end

    # Enhanced validation for connection-level window management
    def self.validate_connection_window_state(window_size : Int32, outstanding_data : Int32) : Nil
      if window_size < 0
        raise ConnectionError.new("Connection window size is negative: #{window_size}", ErrorCode::FlowControlError)
      end

      # Detect potential connection window exhaustion attacks
      if outstanding_data > 0 && window_size == 0
        # This is a legitimate case but should be monitored
        Log.debug { "Connection window exhausted with #{outstanding_data} bytes outstanding" }
      end

      if window_size > MAX_WINDOW_SIZE
        raise ConnectionError.new("Connection window size exceeds maximum: #{window_size}", ErrorCode::FlowControlError)
      end
    end

    # Validate that flow control is properly managed across stream lifecycle
    def self.validate_stream_flow_control_lifecycle(stream_state : StreamState, local_window : Int32, remote_window : Int32) : Nil
      case stream_state
      when .closed?
        # Closed streams should not participate in flow control
        # Note: This is informational, not an error condition
        Log.debug { "Flow control check on closed stream - local: #{local_window}, remote: #{remote_window}" }
      when .idle?
        # Idle streams start with initial window size
        if local_window != INITIAL_WINDOW_SIZE || remote_window != INITIAL_WINDOW_SIZE
          Log.warn { "Idle stream has non-standard window sizes - local: #{local_window}, remote: #{remote_window}" }
        end
      else
        # Active streams should have valid window sizes
        validate_flow_control_state(local_window, remote_window, 0_u32) # stream_id not relevant for state validation
      end
    end
  end
end
