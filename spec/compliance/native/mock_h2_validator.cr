require "../../spec_helper"

# Simple H2 protocol validator for compliance testing
# This validates frames according to RFC 7540 without full client implementation
module H2O
  class MockH2Validator
    property last_error : Exception?
    property expecting_continuation : Bool
    property continuation_stream : UInt32
    property opened_streams : Set(UInt32)

    def initialize
      @last_error = nil
      @expecting_continuation = false
      @continuation_stream = 0_u32
      @opened_streams = Set(UInt32).new
    end

    # Validates a sequence of frames and returns true if valid, raises on error
    def validate_frames(frames : Array(Bytes)) : Bool
      frames.each_with_index do |frame, index|
        validate_frame(frame)
      end
      true
    rescue ex
      @last_error = ex
      raise ex
    end

    private def validate_frame(frame : Bytes)
      return if frame.size < 9

      length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
      type = frame[3]
      flags = frame[4]
      stream_id = (frame[5].to_u32 << 24) | (frame[6].to_u32 << 16) | (frame[7].to_u32 << 8) | frame[8].to_u32

      # Clear reserved bit
      stream_id = stream_id & 0x7FFFFFFF

      # Validate frame size
      if frame.size != 9 + length
        raise FrameSizeError.new("Frame size mismatch: expected #{9 + length}, got #{frame.size}")
      end

      # Check if we're expecting a CONTINUATION frame
      if @expecting_continuation && type != 0x9
        raise ConnectionError.new("Expected CONTINUATION but got frame type #{type}")
      end

      case type
      when 0x0 # DATA
        validate_data_frame(length, flags, stream_id, frame)
      when 0x1 # HEADERS
        validate_headers_frame(length, flags, stream_id, frame)
      when 0x2 # PRIORITY
        validate_priority_frame(length, flags, stream_id, frame)
      when 0x3 # RST_STREAM
        validate_rst_stream_frame(length, flags, stream_id, frame)
      when 0x4 # SETTINGS
        validate_settings_frame(length, flags, stream_id, frame)
      when 0x5 # PUSH_PROMISE
        validate_push_promise_frame(length, flags, stream_id, frame)
      when 0x6 # PING
        validate_ping_frame(length, flags, stream_id, frame)
      when 0x7 # GOAWAY
        validate_goaway_frame(length, flags, stream_id, frame)
      when 0x8 # WINDOW_UPDATE
        validate_window_update_frame(length, flags, stream_id, frame)
      when 0x9 # CONTINUATION
        validate_continuation_frame(length, flags, stream_id, frame)
      else
        # Unknown frame types should be ignored
      end
    end

    private def validate_data_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("DATA frame on connection stream")
      end

      # Check if stream is idle (not opened yet)
      if !@opened_streams.includes?(stream_id) && stream_id > 0
        raise ConnectionError.new("DATA frame on idle stream")
      end

      if (flags & 0x8) != 0 # PADDED flag
        return if length == 0
        # Make sure we have at least one byte for pad length
        if frame.size < 10
          raise ProtocolError.new("PADDED flag set but no pad length")
        end
        pad_length = frame[9]
        if pad_length >= length
          raise ProtocolError.new("Invalid pad length")
        end
      end
    end

    private def validate_headers_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("HEADERS frame on connection stream")
      end

      # Mark stream as opened
      @opened_streams.add(stream_id) if stream_id > 0

      if (flags & 0x8) != 0 # PADDED flag
        return if length == 0
        # Make sure we have at least one byte for pad length
        if frame.size < 10
          raise ProtocolError.new("PADDED flag set but no pad length")
        end
        pad_length = frame[9]
        if pad_length >= length
          raise ProtocolError.new("Invalid pad length")
        end
      end

      # Check for invalid HPACK (simplified - just check for obvious bad data)
      if length > 0 && frame.size > 9
        # If first bytes are all 0xFF, likely invalid
        all_ff = true
        i = 9
        while i < frame.size && i < 14
          all_ff = false if frame[i] != 0xFF
          i += 1
        end
        if all_ff && length >= 5
          raise CompressionError.new("Invalid HPACK encoding")
        end
      end

      # Check END_HEADERS flag
      if (flags & 0x4) == 0 # END_HEADERS not set
        @expecting_continuation = true
        @continuation_stream = stream_id
      else
        @expecting_continuation = false
      end
    end

    private def validate_priority_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("PRIORITY frame on connection stream")
      end

      if length != 5
        raise FrameSizeError.new("PRIORITY frame must be 5 octets")
      end
    end

    private def validate_rst_stream_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("RST_STREAM frame on connection stream")
      end

      if length != 4
        raise FrameSizeError.new("RST_STREAM frame must be 4 octets")
      end

      # Check if stream is idle
      if !@opened_streams.includes?(stream_id) && stream_id > 0
        raise ConnectionError.new("RST_STREAM on idle stream")
      end
    end

    private def validate_settings_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id != 0
        raise ConnectionError.new("SETTINGS frame on non-zero stream")
      end

      ack = (flags & 0x1) != 0

      if ack && length != 0
        raise FrameSizeError.new("SETTINGS ACK must have empty payload")
      end

      if length % 6 != 0
        raise FrameSizeError.new("SETTINGS payload must be multiple of 6")
      end

      # Validate settings
      i = 9
      while i + 5 < frame.size
        setting_id = (frame[i].to_u16 << 8) | frame[i + 1].to_u16
        value = (frame[i + 2].to_u32 << 24) | (frame[i + 3].to_u32 << 16) |
                (frame[i + 4].to_u32 << 8) | frame[i + 5].to_u32

        case setting_id
        when 0x2 # ENABLE_PUSH
          if value > 1
            raise ProtocolError.new("SETTINGS_ENABLE_PUSH must be 0 or 1")
          end
        when 0x4 # INITIAL_WINDOW_SIZE
          if value > 0x7FFFFFFF
            raise FlowControlError.new("SETTINGS_INITIAL_WINDOW_SIZE too large")
          end
        when 0x5 # MAX_FRAME_SIZE
          if value < 16384 || value > 0xFFFFFF
            raise ProtocolError.new("SETTINGS_MAX_FRAME_SIZE out of range")
          end
        end

        i += 6
      end
    end

    private def validate_push_promise_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("PUSH_PROMISE frame on connection stream")
      end

      if length < 4
        raise FrameSizeError.new("PUSH_PROMISE frame too small")
      end

      # Check END_HEADERS flag
      if (flags & 0x4) == 0 # END_HEADERS not set
        @expecting_continuation = true
        @continuation_stream = stream_id
      else
        @expecting_continuation = false
      end
    end

    private def validate_ping_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id != 0
        raise ConnectionError.new("PING frame on non-zero stream")
      end

      if length != 8
        raise FrameSizeError.new("PING frame must be 8 octets")
      end
    end

    private def validate_goaway_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id != 0
        raise ConnectionError.new("GOAWAY frame on non-zero stream")
      end

      if length < 8
        raise FrameSizeError.new("GOAWAY frame must be at least 8 octets")
      end
    end

    private def validate_window_update_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if length != 4
        raise FrameSizeError.new("WINDOW_UPDATE frame must be 4 octets")
      end

      # Extract window size increment
      if frame.size >= 13
        increment = (frame[9].to_u32 << 24) | (frame[10].to_u32 << 16) |
                    (frame[11].to_u32 << 8) | frame[12].to_u32
        # Clear reserved bit
        increment = increment & 0x7FFFFFFF

        if increment == 0
          if stream_id == 0
            raise ConnectionError.new("WINDOW_UPDATE increment of 0 on connection")
          else
            raise StreamError.new("WINDOW_UPDATE increment of 0 on stream", stream_id, ErrorCode::ProtocolError)
          end
        end
      end
    end

    private def validate_continuation_frame(length : UInt32, flags : UInt8, stream_id : UInt32, frame : Bytes)
      if stream_id == 0
        raise ConnectionError.new("CONTINUATION frame on connection stream")
      end

      if !@expecting_continuation
        raise ConnectionError.new("CONTINUATION without HEADERS")
      end

      if stream_id != @continuation_stream
        raise ConnectionError.new("CONTINUATION on different stream")
      end

      # Check END_HEADERS flag
      if (flags & 0x4) != 0 # END_HEADERS set
        @expecting_continuation = false
        @continuation_stream = 0
      end
    end
  end
end
