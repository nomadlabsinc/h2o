module H2O
  class GoawayFrame < Frame
    property last_stream_id : StreamId
    property error_code : ErrorCode
    property debug_data : Bytes

    def initialize(last_stream_id : StreamId, error_code : ErrorCode, debug_data : Bytes = Bytes.empty)
      @last_stream_id = last_stream_id & 0x7fffffff_u32
      @error_code = error_code
      @debug_data = debug_data

      super(8_u32 + debug_data.size.to_u32, FrameType::Goaway, 0_u8, 0_u32)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : GoawayFrame
      raise FrameError.new("GOAWAY frame must have stream ID 0") if stream_id != 0
      raise FrameError.new("GOAWAY frame must have at least 8 bytes") if payload.size < 8

      last_stream_id = ((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                        (payload[2].to_u32 << 8) | payload[3].to_u32) & 0x7fffffff_u32
      error_code = ErrorCode.new((payload[4].to_u32 << 24) | (payload[5].to_u32 << 16) |
                                 (payload[6].to_u32 << 8) | payload[7].to_u32)
      debug_data = payload[8, payload.size - 8]

      frame = new(last_stream_id, error_code, debug_data)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      result = Bytes.new(8 + @debug_data.size)

      result[0] = (@last_stream_id >> 24).to_u8
      result[1] = (@last_stream_id >> 16).to_u8
      result[2] = (@last_stream_id >> 8).to_u8
      result[3] = @last_stream_id.to_u8

      error_value = @error_code.value
      result[4] = (error_value >> 24).to_u8
      result[5] = (error_value >> 16).to_u8
      result[6] = (error_value >> 8).to_u8
      result[7] = error_value.to_u8

      result[8, @debug_data.size].copy_from(@debug_data) unless @debug_data.empty?

      result
    end
  end
end
