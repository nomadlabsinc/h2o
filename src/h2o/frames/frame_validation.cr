module H2O
  # Centralized frame validation following RFC 7540 strict compliance
  # Based on patterns from Go's net/http2 and Rust's h2 libraries
  module FrameValidation
    # DATA frame validation (RFC 7540 Section 6.1)
    def self.validate_data_frame(frame : DataFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("DATA frame with stream ID 0", ErrorCode::ProtocolError)
      end

      # Stream ID must be odd (client-initiated)
      if frame.stream_id % 2 == 0
        raise ConnectionError.new("DATA frame on even stream ID #{frame.stream_id}", ErrorCode::ProtocolError)
      end
    end

    # HEADERS frame validation (RFC 7540 Section 6.2)
    def self.validate_headers_frame(frame : HeadersFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("HEADERS frame with stream ID 0", ErrorCode::ProtocolError)
      end

      # Stream ID must be odd (client-initiated)
      if frame.stream_id % 2 == 0
        raise ConnectionError.new("HEADERS frame on even stream ID #{frame.stream_id}", ErrorCode::ProtocolError)
      end
    end

    # PRIORITY frame validation (RFC 7540 Section 6.3)
    def self.validate_priority_frame(frame : PriorityFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("PRIORITY frame with stream ID 0", ErrorCode::ProtocolError)
      end

      if frame.length != 5
        raise ConnectionError.new("PRIORITY frame invalid length #{frame.length}", ErrorCode::FrameSizeError)
      end

      # Validate stream dependency (if implemented in PriorityFrame)
      # RFC 7540 Section 5.3.1: Stream cannot depend on itself
      if responds_to_dependency_validation?(frame)
        validate_priority_dependency(frame)
      end
    end

    # RST_STREAM frame validation (RFC 7540 Section 6.4)
    def self.validate_rst_stream_frame(frame : RstStreamFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("RST_STREAM frame with stream ID 0", ErrorCode::ProtocolError)
      end

      if frame.length != 4
        raise ConnectionError.new("RST_STREAM frame invalid length #{frame.length}", ErrorCode::FrameSizeError)
      end

      # Validate error code is within valid range
      validate_error_code_range(frame.error_code)
    end

    # SETTINGS frame validation (RFC 7540 Section 6.5)
    def self.validate_settings_frame(frame : SettingsFrame) : Nil
      if frame.stream_id != 0
        raise ConnectionError.new("SETTINGS frame with non-zero stream ID #{frame.stream_id}", ErrorCode::ProtocolError)
      end

      if frame.ack?
        if frame.length != 0
          raise ConnectionError.new("SETTINGS ACK frame must have empty payload", ErrorCode::FrameSizeError)
        end
      else
        if frame.length % 6 != 0
          raise ConnectionError.new("SETTINGS frame payload must be multiple of 6", ErrorCode::FrameSizeError)
        end
      end
    end

    # PUSH_PROMISE frame validation (RFC 7540 Section 6.6)
    def self.validate_push_promise_frame(frame : PushPromiseFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("PUSH_PROMISE frame with stream ID 0", ErrorCode::ProtocolError)
      end

      if frame.length < 4
        raise ConnectionError.new("PUSH_PROMISE frame too short", ErrorCode::FrameSizeError)
      end
    end

    # PING frame validation (RFC 7540 Section 6.7)
    def self.validate_ping_frame(frame : PingFrame) : Nil
      if frame.stream_id != 0
        raise ConnectionError.new("PING frame with non-zero stream ID #{frame.stream_id}", ErrorCode::ProtocolError)
      end

      if frame.length != 8
        raise ConnectionError.new("PING frame invalid length #{frame.length}", ErrorCode::FrameSizeError)
      end
    end

    # GOAWAY frame validation (RFC 7540 Section 6.8)
    def self.validate_goaway_frame(frame : GoawayFrame) : Nil
      if frame.stream_id != 0
        raise ConnectionError.new("GOAWAY frame with non-zero stream ID #{frame.stream_id}", ErrorCode::ProtocolError)
      end

      if frame.length < 8
        raise ConnectionError.new("GOAWAY frame too short", ErrorCode::FrameSizeError)
      end
    end

    # WINDOW_UPDATE frame validation (RFC 7540 Section 6.9)
    def self.validate_window_update_frame(frame : WindowUpdateFrame) : Nil
      if frame.length != 4
        raise ConnectionError.new("WINDOW_UPDATE frame invalid length #{frame.length}", ErrorCode::FrameSizeError)
      end

      if frame.window_size_increment == 0
        if frame.stream_id == 0
          raise ConnectionError.new("WINDOW_UPDATE with zero increment on connection", ErrorCode::ProtocolError)
        else
          raise StreamError.new("WINDOW_UPDATE with zero increment", frame.stream_id, ErrorCode::ProtocolError)
        end
      end
    end

    # CONTINUATION frame validation (RFC 7540 Section 6.10)
    def self.validate_continuation_frame(frame : ContinuationFrame) : Nil
      if frame.stream_id == 0
        raise ConnectionError.new("CONTINUATION frame with stream ID 0", ErrorCode::ProtocolError)
      end
    end

    # Generic frame size validation
    def self.validate_frame_size(length : UInt32, max_frame_size : UInt32) : Nil
      if length > max_frame_size
        raise FrameSizeError.new("Frame size #{length} exceeds maximum #{max_frame_size}")
      end
    end

    # Stream ID constraints validation based on frame type
    def self.validate_stream_id_for_frame_type(frame_type : FrameType, stream_id : StreamId) : Nil
      case frame_type
      when .data?, .headers?, .priority?, .rst_stream?, .push_promise?, .continuation?
        if stream_id == 0
          raise ConnectionError.new("#{frame_type} frame with stream ID 0", ErrorCode::ProtocolError)
        end
        # Additional validation: client-initiated streams must be odd
        if stream_id % 2 == 0
          raise ConnectionError.new("#{frame_type} frame on even stream ID #{stream_id} (server-initiated)", ErrorCode::ProtocolError)
        end
      when .settings?, .ping?, .goaway?
        if stream_id != 0
          raise ConnectionError.new("#{frame_type} frame with non-zero stream ID #{stream_id}", ErrorCode::ProtocolError)
        end
      when .window_update?
        # WINDOW_UPDATE can have stream ID 0 (connection) or non-zero (stream)
        # No validation needed here
      end
    end

    # Enhanced frame flag validation
    def self.validate_frame_flags(frame : Frame) : Nil
      case frame
      when DataFrame
        validate_data_frame_flags(frame)
      when HeadersFrame
        validate_headers_frame_flags(frame)
      when SettingsFrame
        validate_settings_frame_flags(frame)
      when PingFrame
        validate_ping_frame_flags(frame)
      when GoawayFrame
        validate_goaway_frame_flags(frame)
      when WindowUpdateFrame
        validate_window_update_frame_flags(frame)
      when RstStreamFrame
        validate_rst_stream_frame_flags(frame)
      when PriorityFrame
        validate_priority_frame_flags(frame)
      when ContinuationFrame
        validate_continuation_frame_flags(frame)
      when PushPromiseFrame
        validate_push_promise_frame_flags(frame)
      end
    end

    # Frame-specific flag validation methods
    private def self.validate_data_frame_flags(frame : DataFrame) : Nil
      # RFC 7540 Section 6.1: DATA frame flags
      # Defined flags: END_STREAM (0x1), PADDED (0x8)
      valid_flags = 0x09_u8 # END_STREAM | PADDED
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("DATA frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_headers_frame_flags(frame : HeadersFrame) : Nil
      # RFC 7540 Section 6.2: HEADERS frame flags
      # Defined flags: END_STREAM (0x1), END_HEADERS (0x4), PADDED (0x8), PRIORITY (0x20)
      valid_flags = 0x2D_u8 # END_STREAM | END_HEADERS | PADDED | PRIORITY
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("HEADERS frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_settings_frame_flags(frame : SettingsFrame) : Nil
      # RFC 7540 Section 6.5: SETTINGS frame flags
      # Defined flags: ACK (0x1)
      valid_flags = 0x01_u8 # ACK
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("SETTINGS frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_ping_frame_flags(frame : PingFrame) : Nil
      # RFC 7540 Section 6.7: PING frame flags
      # Defined flags: ACK (0x1)
      valid_flags = 0x01_u8 # ACK
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("PING frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_goaway_frame_flags(frame : GoawayFrame) : Nil
      # RFC 7540 Section 6.8: GOAWAY frame has no defined flags
      if frame.flags != 0
        raise ConnectionError.new("GOAWAY frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_window_update_frame_flags(frame : WindowUpdateFrame) : Nil
      # RFC 7540 Section 6.9: WINDOW_UPDATE frame has no defined flags
      if frame.flags != 0
        raise ConnectionError.new("WINDOW_UPDATE frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_rst_stream_frame_flags(frame : RstStreamFrame) : Nil
      # RFC 7540 Section 6.4: RST_STREAM frame has no defined flags
      if frame.flags != 0
        raise ConnectionError.new("RST_STREAM frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_priority_frame_flags(frame : PriorityFrame) : Nil
      # RFC 7540 Section 6.3: PRIORITY frame has no defined flags
      if frame.flags != 0
        raise ConnectionError.new("PRIORITY frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_continuation_frame_flags(frame : ContinuationFrame) : Nil
      # RFC 7540 Section 6.10: CONTINUATION frame flags
      # Defined flags: END_HEADERS (0x4)
      valid_flags = 0x04_u8 # END_HEADERS
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("CONTINUATION frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    private def self.validate_push_promise_frame_flags(frame : PushPromiseFrame) : Nil
      # RFC 7540 Section 6.6: PUSH_PROMISE frame flags
      # Defined flags: END_HEADERS (0x4), PADDED (0x8)
      valid_flags = 0x0C_u8 # END_HEADERS | PADDED
      if (frame.flags & ~valid_flags) != 0
        raise ConnectionError.new("PUSH_PROMISE frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    # Validate error codes are within defined ranges
    private def self.validate_error_code_range(error_code : ErrorCode) : Nil
      # RFC 7540 Section 7: Error codes are 32-bit values
      # Defined error codes: 0x0 to 0xd, with room for extension
      case error_code
      when ErrorCode::NoError, ErrorCode::ProtocolError, ErrorCode::InternalError,
           ErrorCode::FlowControlError, ErrorCode::SettingsTimeout, ErrorCode::StreamClosed,
           ErrorCode::FrameSizeError, ErrorCode::RefusedStream, ErrorCode::Cancel,
           ErrorCode::CompressionError, ErrorCode::ConnectError, ErrorCode::EnhanceYourCalm,
           ErrorCode::InadequateSecurity, ErrorCode::Http11Required
        # Valid defined error codes
      else
        # Unknown error codes are allowed but logged
        Log.debug { "Unknown error code: #{error_code.value}" }
      end
    end

    # Priority dependency validation (if frame supports it)
    private def self.responds_to_dependency_validation?(frame : PriorityFrame) : Bool
      # This would need to be implemented based on the actual PriorityFrame structure
      # For now, return false as a placeholder
      false
    end

    private def self.validate_priority_dependency(frame : PriorityFrame) : Nil
      # RFC 7540 Section 5.3.1: A stream cannot depend on itself
      # This would need frame.stream_dependency implementation
      # raise ConnectionError.new("Stream #{frame.stream_id} cannot depend on itself", ErrorCode::ProtocolError)
    end

    # Comprehensive frame validation combining all checks
    def self.validate_frame_comprehensive(frame : Frame) : Nil
      # Basic frame size validation
      validate_frame_size(frame.length, Frame::MAX_FRAME_SIZE)

      # Stream ID validation
      validate_stream_id_for_frame_type(frame.frame_type, frame.stream_id)

      # Frame-specific validation
      case frame
      when DataFrame
        validate_data_frame(frame)
      when HeadersFrame
        validate_headers_frame(frame)
      when PriorityFrame
        validate_priority_frame(frame)
      when RstStreamFrame
        validate_rst_stream_frame(frame)
      when SettingsFrame
        validate_settings_frame(frame)
      when PushPromiseFrame
        validate_push_promise_frame(frame)
      when PingFrame
        validate_ping_frame(frame)
      when GoawayFrame
        validate_goaway_frame(frame)
      when WindowUpdateFrame
        validate_window_update_frame(frame)
      when ContinuationFrame
        validate_continuation_frame(frame)
      end

      # Frame flag validation
      validate_frame_flags(frame)
    end
  end
end
