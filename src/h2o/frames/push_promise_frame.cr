module H2O
  class PushPromiseFrame < Frame
    FLAG_END_HEADERS = 0x4_u8
    FLAG_PADDED      = 0x8_u8

    property promised_stream_id : StreamId
    property header_block : Bytes
    property padding_length : UInt8

    def initialize(stream_id : StreamId, promised_stream_id : StreamId, header_block : Bytes,
                   end_headers : Bool = false, padding_length : UInt8 = 0_u8)
      raise FrameError.new("PUSH_PROMISE frame must have non-zero stream ID") if stream_id == 0

      @promised_stream_id = promised_stream_id & 0x7fffffff_u32
      @header_block = header_block
      @padding_length = padding_length

      flags = 0_u8
      flags |= FLAG_END_HEADERS if end_headers
      flags |= FLAG_PADDED if padding_length > 0

      total_length = 4_u32 + header_block.size.to_u32
      total_length += 1 if padded?
      total_length += padding_length

      super(total_length, FrameType::PushPromise, flags, stream_id)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : PushPromiseFrame
      raise FrameError.new("PUSH_PROMISE frame must have non-zero stream ID") if stream_id == 0
      raise FrameError.new("PUSH_PROMISE frame must have at least 4 bytes") if payload.size < 4

      offset = 0
      padding_length = 0_u8

      if flags & FLAG_PADDED != 0
        padding_length = payload[0]
        offset += 1
      end

      raise FrameError.new("PUSH_PROMISE frame insufficient data") if payload.size < offset + 4

      promised_stream_id = ((payload[offset].to_u32 << 24) | (payload[offset + 1].to_u32 << 16) |
                            (payload[offset + 2].to_u32 << 8) | payload[offset + 3].to_u32) & 0x7fffffff_u32
      offset += 4

      header_block_end = payload.size - padding_length
      raise FrameError.new("PUSH_PROMISE frame padding exceeds payload") if header_block_end < offset

      header_block = payload[offset, header_block_end - offset]

      end_headers = (flags & FLAG_END_HEADERS) != 0
      frame = new(stream_id, promised_stream_id, header_block, end_headers, padding_length)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      size = 4 + @header_block.size
      size += 1 if padded?
      size += @padding_length

      result = Bytes.new(size)
      offset = 0

      if padded?
        result[0] = @padding_length
        offset += 1
      end

      result[offset] = (@promised_stream_id >> 24).to_u8
      result[offset + 1] = (@promised_stream_id >> 16).to_u8
      result[offset + 2] = (@promised_stream_id >> 8).to_u8
      result[offset + 3] = @promised_stream_id.to_u8
      offset += 4

      result[offset, @header_block.size].copy_from(@header_block)
      result
    end

    def end_headers? : Bool
      (@flags & FLAG_END_HEADERS) != 0
    end

    def padded? : Bool
      (@flags & FLAG_PADDED) != 0
    end
  end
end
