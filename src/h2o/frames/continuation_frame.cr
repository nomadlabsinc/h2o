module H2O
  class ContinuationFrame < Frame
    FLAG_END_HEADERS = 0x4_u8

    property header_block : Bytes

    def initialize(stream_id : StreamId, header_block : Bytes, end_headers : Bool = false)
      raise FrameError.new("CONTINUATION frame must have non-zero stream ID") if stream_id == 0

      @header_block = header_block
      flags = end_headers ? FLAG_END_HEADERS : 0_u8

      super(header_block.size.to_u32, FrameType::Continuation, flags, stream_id)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : ContinuationFrame
      raise FrameError.new("CONTINUATION frame must have non-zero stream ID") if stream_id == 0

      end_headers = (flags & FLAG_END_HEADERS) != 0
      frame = new(stream_id, payload, end_headers)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      @header_block
    end

    def end_headers? : Bool
      (@flags & FLAG_END_HEADERS) != 0
    end
  end
end
