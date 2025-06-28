module H2O
  # Strict CONTINUATION frame validation following Go net/http2 and Rust h2 patterns
  # Based on RFC 7540 Section 6.10 and security best practices
  module ContinuationValidation
    # Maximum CONTINUATION frames per stream (prevent DoS)
    MAX_CONTINUATION_FRAMES = 100

    # Maximum total size for fragmented headers
    MAX_FRAGMENTED_HEADER_SIZE = 262144 # 256KB

    # Maximum time window for CONTINUATION sequence
    MAX_CONTINUATION_DURATION = 30.seconds

    # Validate CONTINUATION frame sequence integrity
    def self.validate_continuation_sequence(stream_id : StreamId,
                                            existing_fragments : Hash(StreamId, HeaderFragmentState),
                                            continuation_frame : ContinuationFrame) : Nil
      # RFC 7540 Section 6.10: CONTINUATION frames MUST be on same stream
      # as preceding HEADERS/PUSH_PROMISE frame
      unless existing_fragments.has_key?(stream_id)
        raise ConnectionError.new("CONTINUATION frame #{stream_id} without preceding HEADERS frame", ErrorCode::ProtocolError)
      end

      fragment_state = existing_fragments[stream_id]

      # Validate continuation count limits
      new_count = fragment_state[:continuation_count] + 1
      if new_count > MAX_CONTINUATION_FRAMES
        raise ConnectionError.new("Too many CONTINUATION frames: #{new_count}", ErrorCode::EnhanceYourCalm)
      end

      # Validate accumulated size
      new_size = fragment_state[:accumulated_size] + continuation_frame.header_block.size
      if new_size > MAX_FRAGMENTED_HEADER_SIZE
        raise ConnectionError.new("CONTINUATION frames exceed size limit: #{new_size} bytes", ErrorCode::EnhanceYourCalm)
      end

      # Validate timing to prevent slow header attacks
      if Time.utc - fragment_state[:start_time] > MAX_CONTINUATION_DURATION
        raise ConnectionError.new("CONTINUATION sequence took too long", ErrorCode::EnhanceYourCalm)
      end

      # RFC 7540 Section 6.10: No other frames can be sent on connection
      # until CONTINUATION sequence is complete (this should be enforced
      # by the frame ordering in the receiver loop)
    end

    # Validate CONTINUATION frame flags
    def self.validate_continuation_flags(frame : ContinuationFrame) : Nil
      # RFC 7540 Section 6.10: Only END_HEADERS flag is defined
      # Bits 0-6 must be unset, only bit 2 (END_HEADERS) can be set
      invalid_flags = frame.flags & 0xFB # All bits except END_HEADERS (0x4)
      if invalid_flags != 0
        raise ConnectionError.new("CONTINUATION frame has invalid flags: 0x#{frame.flags.to_s(16)}", ErrorCode::ProtocolError)
      end
    end

    # Validate CONTINUATION frame payload
    def self.validate_continuation_payload(frame : ContinuationFrame) : Nil
      # RFC 7540 Section 6.10: CONTINUATION frames must have payload
      if frame.header_block.empty?
        raise ConnectionError.new("CONTINUATION frame with empty payload", ErrorCode::ProtocolError)
      end

      # Validate payload size is reasonable
      if frame.header_block.size > 65536 # 64KB max per frame
        raise ConnectionError.new("CONTINUATION frame payload too large: #{frame.header_block.size} bytes", ErrorCode::FrameSizeError)
      end
    end

    # Validate final assembled headers from CONTINUATION sequence
    def self.validate_assembled_headers(total_size : Int32, header_data : Bytes, max_header_list_size : Int32) : Nil
      # Final size validation
      if total_size > max_header_list_size
        raise ConnectionError.new("Assembled header block too large: #{total_size} bytes", ErrorCode::CompressionError)
      end

      # Validate the assembled data is not suspiciously compressible (potential bomb)
      if header_data.size > 0
        # Check for repetitive patterns that might indicate compression bomb
        validate_header_compression_safety(header_data)
      end
    end

    # Enhanced validation for interleaved frames during CONTINUATION sequence
    def self.validate_no_interleaved_frames(expected_stream_id : StreamId, frame : Frame) : Nil
      # RFC 7540 Section 6.2: No other frames can be sent on the connection
      # between HEADERS and final CONTINUATION frame, except:
      # - PRIORITY frames for any stream
      # - RST_STREAM frames for the same stream
      # - CONNECTION frames (SETTINGS, PING, GOAWAY, WINDOW_UPDATE with stream_id=0)

      case frame
      when PriorityFrame
        # PRIORITY frames are allowed for any stream
        return
      when RstStreamFrame
        # RST_STREAM allowed only for the same stream
        if frame.stream_id != expected_stream_id
          raise ConnectionError.new("RST_STREAM for different stream during CONTINUATION sequence", ErrorCode::ProtocolError)
        end
      when SettingsFrame, PingFrame, GoawayFrame
        # Connection-level frames are allowed
        return
      when WindowUpdateFrame
        # WINDOW_UPDATE allowed only for connection (stream_id=0) or same stream
        if frame.stream_id != 0 && frame.stream_id != expected_stream_id
          raise ConnectionError.new("WINDOW_UPDATE for different stream during CONTINUATION sequence", ErrorCode::ProtocolError)
        end
      else
        # All other frame types are forbidden during CONTINUATION sequence
        raise ConnectionError.new("#{frame.frame_type} frame not allowed during CONTINUATION sequence", ErrorCode::ProtocolError)
      end
    end

    # Check for potential compression bombs in header data
    private def self.validate_header_compression_safety(data : Bytes) : Nil
      return if data.size < 100 # Too small to be concerning

      # Simple check for excessive repetition
      # Count unique byte sequences to detect artificial inflation
      unique_sequences = Set(Bytes).new
      window_size = 8

      i = 0
      while i + window_size <= data.size
        sequence = data[i, window_size]
        unique_sequences << sequence
        i += 1
      end

      # If uniqueness ratio is very low, it might be a bomb
      uniqueness_ratio = unique_sequences.size.to_f / (data.size - window_size + 1).to_f
      if uniqueness_ratio < 0.1 && data.size > 1000
        raise ConnectionError.new("Suspicious header data pattern detected", ErrorCode::EnhanceYourCalm)
      end
    end
  end
end
