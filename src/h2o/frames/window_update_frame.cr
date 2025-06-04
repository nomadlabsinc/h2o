module H2O
  class WindowUpdateFrame < Frame
    property window_size_increment : UInt32

    def initialize(stream_id : StreamId, window_size_increment : UInt32)
      raise FrameError.new("WINDOW_UPDATE increment must be non-zero") if window_size_increment == 0
      raise FrameError.new("WINDOW_UPDATE increment too large") if window_size_increment > 0x7fffffff_u32

      @window_size_increment = window_size_increment

      super(4_u32, FrameType::WindowUpdate, 0_u8, stream_id)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : WindowUpdateFrame
      raise FrameError.new("WINDOW_UPDATE frame must have 4-byte payload") if payload.size != 4

      window_size_increment = ((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                               (payload[2].to_u32 << 8) | payload[3].to_u32) & 0x7fffffff_u32

      raise FrameError.new("WINDOW_UPDATE increment must be non-zero") if window_size_increment == 0

      frame = allocate
      frame.initialize_from_payload(length, flags, stream_id, window_size_increment)
      frame
    end

    def payload_to_bytes : Bytes
      result = Bytes.new(4)
      result[0] = (@window_size_increment >> 24).to_u8
      result[1] = (@window_size_increment >> 16).to_u8
      result[2] = (@window_size_increment >> 8).to_u8
      result[3] = @window_size_increment.to_u8
      result
    end

    protected def initialize_from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, window_size_increment : UInt32)
      @length = length
      @frame_type = FrameType::WindowUpdate
      @flags = flags
      @stream_id = stream_id
      @window_size_increment = window_size_increment
    end
  end
end
