module H2O
  abstract class Frame
    MAX_FRAME_SIZE    = 16777215_u32
    FRAME_HEADER_SIZE =         9_u8

    property length : UInt32
    property frame_type : FrameType
    property flags : UInt8
    property stream_id : StreamId

    def initialize(@length : UInt32, @frame_type : FrameType, @flags : UInt8, @stream_id : StreamId)
      validate_length
      validate_stream_id
    end

    def self.from_io(io : IO) : Frame
      BufferPool.with_header_buffer do |header_buffer|
        header = header_buffer[0, FRAME_HEADER_SIZE]
        io.read_fully(header)

        length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
        frame_type = FrameType.new(header[3])
        flags = header[4]
        stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) | (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32

        payload = BufferPool.get_frame_buffer(length.to_i32)[0, length]
        io.read_fully(payload) if length > 0

        frame = create_frame(frame_type, length, flags, stream_id, payload)
        # Note: payload buffer will be returned by frame when it's finalized
        frame
      end
    end

    def to_bytes : Bytes
      BufferPool.with_header_buffer do |header_buffer|
        header = header_buffer[0, FRAME_HEADER_SIZE]

        header[0] = ((@length >> 16) & 0xff).to_u8
        header[1] = ((@length >> 8) & 0xff).to_u8
        header[2] = (@length & 0xff).to_u8
        header[3] = @frame_type.value
        header[4] = @flags
        header[5] = ((@stream_id >> 24) & 0xff).to_u8
        header[6] = ((@stream_id >> 16) & 0xff).to_u8
        header[7] = ((@stream_id >> 8) & 0xff).to_u8
        header[8] = (@stream_id & 0xff).to_u8

        begin
          payload_bytes = payload_to_bytes
          payload_size = payload_bytes.size

          # Prevent arithmetic overflow and enforce HTTP/2 frame size limits
          # HTTP/2 spec: frame size must not exceed 2^24-1 (16,777,215) bytes
          max_frame_payload = 16_777_215
          max_safe_payload = Int32::MAX - FRAME_HEADER_SIZE
          max_allowed_payload = Math.min(max_frame_payload, max_safe_payload)

          if payload_size < 0
            raise ArgumentError.new("Frame payload size cannot be negative: #{payload_size}")
          end

          if payload_size > max_allowed_payload
            raise ArgumentError.new("Frame payload too large: #{payload_size} bytes (max: #{max_allowed_payload})")
          end

          # Use explicit type checking to prevent any overflow during addition
          total_size_i64 = FRAME_HEADER_SIZE.to_i64 + payload_size.to_i64
          if total_size_i64 > Int32::MAX
            raise ArgumentError.new("Total frame size would overflow: #{total_size_i64}")
          end

          total_size = total_size_i64.to_i32
        rescue ex : OverflowError
          raise ArgumentError.new("Arithmetic overflow in frame size calculation: #{self.class} with payload size #{payload_size rescue "unknown"}")
        end

        BufferPool.with_frame_buffer(total_size) do |frame_buffer|
          frame_buffer.copy_from(header)
          frame_buffer[FRAME_HEADER_SIZE, payload_bytes.size].copy_from(payload_bytes)
          result = Bytes.new(total_size)
          result.copy_from(frame_buffer[0, total_size])
          result
        end
      end
    end

    abstract def payload_to_bytes : Bytes

    # Default reset for object pool reuse - subclasses should override
    def reset_for_reuse : Nil
      @flags = 0_u8
      @length = 0_u32
      @stream_id = 0_u32
    end

    protected def set_length(length : UInt32) : Nil
      @length = length
    end

    protected def set_flags(flags : UInt8) : Nil
      @flags = flags
    end

    private def self.create_frame(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : FramePayload) : Frame
      create_frame_by_type(frame_type, length, flags, stream_id, payload)
    end

    private def self.create_frame_by_type(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : FramePayload) : Frame
      case frame_type
      when .data?
        DataFrame.from_payload(length, flags, stream_id, payload)
      when .headers?, .continuation?
        create_header_frame(frame_type, length, flags, stream_id, payload)
      when .priority?, .rst_stream?
        create_control_frame(frame_type, length, flags, stream_id, payload)
      when .settings?, .ping?, .goaway?, .window_update?
        create_connection_frame(frame_type, length, flags, stream_id, payload)
      when .push_promise?
        PushPromiseFrame.from_payload(length, flags, stream_id, payload)
      else
        raise FrameError.new("Unknown frame type: #{frame_type}")
      end
    end

    private def self.create_header_frame(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : Frame
      case frame_type
      when .headers?
        HeadersFrame.from_payload(length, flags, stream_id, payload)
      when .continuation?
        ContinuationFrame.from_payload(length, flags, stream_id, payload)
      else
        raise FrameError.new("Invalid header frame type: #{frame_type}")
      end
    end

    private def self.create_control_frame(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : Frame
      case frame_type
      when .priority?
        PriorityFrame.from_payload(length, flags, stream_id, payload)
      when .rst_stream?
        RstStreamFrame.from_payload(length, flags, stream_id, payload)
      else
        raise FrameError.new("Invalid control frame type: #{frame_type}")
      end
    end

    private def self.create_connection_frame(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : Frame
      case frame_type
      when .settings?
        SettingsFrame.from_payload(length, flags, stream_id, payload)
      when .ping?
        PingFrame.from_payload(length, flags, stream_id, payload)
      when .goaway?
        GoawayFrame.from_payload(length, flags, stream_id, payload)
      when .window_update?
        WindowUpdateFrame.from_payload(length, flags, stream_id, payload)
      else
        raise FrameError.new("Invalid connection frame type: #{frame_type}")
      end
    end

    private def validate_length : Nil
      raise FrameError.new("Frame length exceeds maximum: #{@length}") if @length > MAX_FRAME_SIZE
    end

    private def validate_stream_id : Nil
      if @stream_id > 0x7fffffff_u32
        raise FrameError.new("Invalid stream ID: #{@stream_id}")
      end
    end
  end
end
