module H2O
  class DataFrame < Frame
    FLAG_END_STREAM = 0x1_u8
    FLAG_PADDED     = 0x8_u8

    property data : Bytes
    property padding_length : UInt8

    def initialize(stream_id : StreamId, data : Bytes, flags : UInt8 = 0_u8, padding_length : UInt8 = 0_u8)
      @data = data
      @padding_length = padding_length

      total_length = data.size.to_u32
      total_length += 1 if (flags & FLAG_PADDED) != 0
      total_length += padding_length

      super(total_length, FrameType::Data, flags, stream_id)
      validate_stream_id_non_zero
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : DataFrame
      if flags & FLAG_PADDED != 0
        raise FrameError.new("Invalid DATA frame: empty payload with PADDED flag") if payload.empty?

        padding_length = payload[0]
        raise FrameError.new("Invalid DATA frame: padding length exceeds payload") if padding_length >= payload.size

        data_end = payload.size - padding_length
        data = payload[1, data_end - 1]

        frame = new(stream_id, data, flags, padding_length)
        frame.set_length(length)
        frame
      else
        data = payload
        frame = new(stream_id, data, flags, 0_u8)
        frame.set_length(length)
        frame
      end
    end

    def payload_to_bytes : Bytes
      # Validate data size to prevent overflow
      max_data_size = 16_777_215 - 1 - @padding_length # HTTP/2 max frame size minus padding overhead
      if @data.size > max_data_size
        raise ArgumentError.new("Data frame payload too large: #{@data.size} bytes (max: #{max_data_size})")
      end

      if padded?
        # Check for overflow before allocation
        total_size = 1 + @data.size + @padding_length
        if total_size < 0 || total_size > 16_777_215
          raise ArgumentError.new("Padded frame total size overflow: #{total_size}")
        end

        # Don't use BufferPool to avoid memory corruption
        result = Bytes.new(total_size)
        result[0] = @padding_length
        result[1, @data.size].copy_from(@data)
        result
      else
        @data
      end
    end

    def end_stream? : Bool
      (@flags & FLAG_END_STREAM) != 0
    end

    def padded? : Bool
      (@flags & FLAG_PADDED) != 0
    end

    # DISABLED: reset_for_reuse causes memory corruption with object pooling
    # def reset_for_reuse : Nil
    #   @data = Bytes.empty
    #   @flags = 0_u8
    #   @length = 0_u32
    #   @padding_length = 0_u8
    #   @stream_id = 0_u32
    # end

    def set_data(data : Bytes) : Nil
      @data = data
      recalculate_length
    end

    private def recalculate_length : Nil
      total_length = @data.size.to_u32
      total_length += 1 if (@flags & FLAG_PADDED) != 0
      total_length += @padding_length
      @length = total_length
    end

    private def validate_stream_id_non_zero : Nil
      raise FrameError.new("DATA frame must have non-zero stream ID") if @stream_id == 0
    end
  end
end
