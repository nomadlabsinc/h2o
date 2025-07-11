module H2O
  class HeadersFrame < Frame
    FLAG_END_STREAM  =  0x1_u8
    FLAG_END_HEADERS =  0x4_u8
    FLAG_PADDED      =  0x8_u8
    FLAG_PRIORITY    = 0x20_u8

    property header_block : Bytes
    property padding_length : UInt8
    property priority_exclusive : Bool
    property priority_dependency : StreamId
    property priority_weight : UInt8

    def initialize(stream_id : StreamId, header_block : Bytes, flags : UInt8 = 0_u8,
                   padding_length : UInt8 = 0_u8, priority_exclusive : Bool = false,
                   priority_dependency : StreamId = 0_u32, priority_weight : UInt8 = 0_u8)
      @header_block = header_block
      @padding_length = padding_length
      @priority_exclusive = priority_exclusive
      @priority_dependency = priority_dependency
      @priority_weight = priority_weight

      total_length = header_block.size.to_u32
      total_length += 1 if (flags & FLAG_PADDED) != 0
      total_length += 5 if (flags & FLAG_PRIORITY) != 0
      total_length += padding_length

      super(total_length, FrameType::Headers, flags, stream_id)
      validate_stream_id_non_zero
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : HeadersFrame
      offset = 0
      padding_length = 0_u8
      priority_exclusive = false
      priority_dependency = 0_u32
      priority_weight = 0_u8

      if flags & FLAG_PADDED != 0
        raise FrameError.new("Invalid HEADERS frame: empty payload with PADDED flag") if payload.empty?
        padding_length = payload[0]
        offset += 1
      end

      if flags & FLAG_PRIORITY != 0
        raise FrameError.new("Invalid HEADERS frame: insufficient data for priority") if payload.size < offset + 5

        priority_data = ((payload[offset].to_u32 << 24) | (payload[offset + 1].to_u32 << 16) |
                         (payload[offset + 2].to_u32 << 8) | payload[offset + 3].to_u32)
        priority_exclusive = (priority_data & 0x80000000_u32) != 0
        priority_dependency = priority_data & 0x7fffffff_u32
        priority_weight = payload[offset + 4]
        offset += 5
      end

      header_block_end = payload.size - padding_length
      raise FrameError.new("Invalid HEADERS frame: padding exceeds payload") if header_block_end < offset

      header_block = payload[offset, header_block_end - offset]

      frame = new(stream_id, header_block, flags, padding_length,
        priority_exclusive, priority_dependency, priority_weight)
      frame.set_length(length)
      frame
    end

    def payload_to_bytes : Bytes
      size = @header_block.size
      size += 1 if padded?
      size += 5 if priority?
      size += @padding_length

      # Don't use BufferPool to avoid memory corruption
      result = Bytes.new(size)
      offset = 0

      if padded?
        result[0] = @padding_length
        offset += 1
      end

      if priority?
        priority_data = @priority_dependency
        priority_data |= 0x80000000_u32 if @priority_exclusive
        result[offset] = ((priority_data >> 24) & 0xff).to_u8
        result[offset + 1] = ((priority_data >> 16) & 0xff).to_u8
        result[offset + 2] = ((priority_data >> 8) & 0xff).to_u8
        result[offset + 3] = (priority_data & 0xff).to_u8
        result[offset + 4] = @priority_weight
        offset += 5
      end

      result[offset, @header_block.size].copy_from(@header_block)
      result
    end

    def end_stream? : Bool
      (@flags & FLAG_END_STREAM) != 0
    end

    def end_headers? : Bool
      (@flags & FLAG_END_HEADERS) != 0
    end

    def padded? : Bool
      (@flags & FLAG_PADDED) != 0
    end

    def priority? : Bool
      (@flags & FLAG_PRIORITY) != 0
    end


    def set_header_block(header_block : Bytes) : Nil
      @header_block = header_block
      recalculate_length
    end

    private def recalculate_length : Nil
      total_length = @header_block.size.to_u32
      total_length += 1 if (@flags & FLAG_PADDED) != 0
      total_length += 5 if (@flags & FLAG_PRIORITY) != 0
      total_length += @padding_length
      @length = total_length
    end

    private def validate_stream_id_non_zero : Nil
      raise FrameError.new("HEADERS frame must have non-zero stream ID") if @stream_id == 0
    end
  end
end
