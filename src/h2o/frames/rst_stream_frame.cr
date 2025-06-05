module H2O
  class RstStreamFrame < Frame
    property error_code : ErrorCode

    def initialize(stream_id : StreamId, error_code : ErrorCode)
      raise FrameError.new("RST_STREAM frame must have non-zero stream ID") if stream_id == 0

      @error_code = error_code

      super(4_u32, FrameType::RstStream, 0_u8, stream_id)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : RstStreamFrame
      raise FrameError.new("RST_STREAM frame must have non-zero stream ID") if stream_id == 0
      raise FrameError.new("RST_STREAM frame must have 4-byte payload") if payload.size != 4

      error_code = ErrorCode.new((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                                 (payload[2].to_u32 << 8) | payload[3].to_u32)

      frame = new(stream_id, error_code)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      result = Bytes.new(4)
      error_value = @error_code.value
      result[0] = ((error_value >> 24) & 0xff).to_u8
      result[1] = ((error_value >> 16) & 0xff).to_u8
      result[2] = ((error_value >> 8) & 0xff).to_u8
      result[3] = (error_value & 0xff).to_u8
      result
    end
  end
end
