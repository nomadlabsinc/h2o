module H2O::HPACK
  class Decoder
    property dynamic_table : DynamicTable
    property security_limits : HpackSecurityLimits
    property total_decompressed_size : Int32

    def initialize(table_size : Int32 = DynamicTable::DEFAULT_SIZE, @security_limits : HpackSecurityLimits = HpackSecurityLimits.new)
      @dynamic_table = DynamicTable.new(table_size)
      @total_decompressed_size = 0
    end

    def decode(data : Bytes) : Headers
      # Pre-validation: Check compression ratio
      if data.size > 0
        compression_ratio = data.size.to_f64 / @security_limits.max_decompressed_size.to_f64
        if compression_ratio > @security_limits.compression_ratio_limit
          raise HpackBombError.new("Suspicious compression ratio: #{compression_ratio}")
        end
      end

      headers = Headers.new
      io = IO::Memory.new(data)
      @total_decompressed_size = 0

      while io.pos < io.size
        decode_header(io, headers)
      end

      # Final validation
      validate_final_headers(headers)
      headers
    end

    private def decode_header(io : IO, headers : Headers) : Nil
      byte = io.read_byte
      return unless byte

      if (byte & 0x80) != 0
        decode_indexed_header(io, headers, byte)
      elsif (byte & 0x40) != 0
        decode_literal_with_incremental_indexing(io, headers, byte)
      elsif (byte & 0x20) != 0
        decode_dynamic_table_size_update(io, byte)
      else
        decode_literal_without_indexing(io, headers, byte)
      end
    end

    private def decode_indexed_header(io : IO, headers : Headers, first_byte : UInt8) : Nil
      index_raw = decode_integer(io, first_byte & 0x7f, 7)

      # Convert UInt32 to Int32 with bounds checking
      if index_raw > Int32::MAX
        raise CompressionError.new("Header index too large: #{index_raw}")
      end
      index = index_raw.to_i32

      entry = @dynamic_table[index]

      raise CompressionError.new("Invalid header index: #{index}") unless entry

      add_header_safely(headers, entry.name, entry.value)
    end

    private def decode_literal_with_incremental_indexing(io : IO, headers : Headers, first_byte : UInt8) : Nil
      name, value = decode_literal_header(io, first_byte & 0x3f, 6)
      add_header_safely(headers, name, value)
      @dynamic_table.add(name, value)
    end

    private def decode_literal_without_indexing(io : IO, headers : Headers, first_byte : UInt8) : Nil
      name, value = decode_literal_header(io, first_byte & 0x0f, 4)
      add_header_safely(headers, name, value)
    end

    private def decode_dynamic_table_size_update(io : IO, first_byte : UInt8) : Nil
      size_raw = decode_integer(io, first_byte & 0x1f, 5)

      # Convert UInt32 to Int32 with bounds checking
      if size_raw > Int32::MAX
        raise CompressionError.new("Dynamic table size too large: #{size_raw}")
      end
      size = size_raw.to_i32

      # Validate against security limits
      if size > @security_limits.max_dynamic_table_size
        raise HpackBombError.new("Dynamic table size exceeds security limit: #{size} > #{@security_limits.max_dynamic_table_size}")
      end

      @dynamic_table.resize(size)
    end

    private def decode_literal_header(io : IO, name_index : UInt8, prefix_bits : IntegerValue) : HeaderEntry
      if name_index == 0
        name = decode_string(io)
      else
        index_raw = decode_integer(io, name_index, prefix_bits)

        # Convert UInt32 to Int32 with bounds checking
        if index_raw > Int32::MAX
          raise CompressionError.new("Header name index too large: #{index_raw}")
        end
        index = index_raw.to_i32

        entry = @dynamic_table[index]
        raise CompressionError.new("Invalid header name index: #{index}") unless entry
        name = entry.name
      end

      value = decode_string(io)
      {name, value}
    end

    private def decode_string(io : IO) : String
      first_byte = io.read_byte
      raise CompressionError.new("Unexpected end of data") unless first_byte

      huffman_encoded = (first_byte & 0x80) != 0
      length_raw = decode_integer(io, first_byte & 0x7f, 7)

      # Convert UInt32 to Int32 with bounds checking for string length
      if length_raw > Int32::MAX
        raise CompressionError.new("String length too large: #{length_raw}")
      end
      length = length_raw.to_i32

      # Validate against security limits
      if length > @security_limits.max_string_length
        raise HpackBombError.new("String length exceeds security limit: #{length} > #{@security_limits.max_string_length}")
      end

      if length <= BufferPool::MAX_HEADER_BUFFER_SIZE
        BufferPool.with_header_buffer do |buffer|
          data = buffer[0, length]
          bytes_read = io.read(data)
          raise CompressionError.new("Unexpected end of data") if bytes_read != length

          if huffman_encoded
            Huffman.decode(data, @security_limits.max_string_length)
          else
            String.new(data)
          end
        end
      else
        # For very large strings, fallback to direct allocation
        data = Bytes.new(length)
        bytes_read = io.read(data)
        raise CompressionError.new("Unexpected end of data") if bytes_read != length

        if huffman_encoded
          Huffman.decode(data, @security_limits.max_string_length)
        else
          String.new(data)
        end
      end
    end

    private def decode_integer(io : IO, value : UInt8, prefix_bits : Int32) : UInt32
      max_value = (1_u32 << prefix_bits) - 1

      if value < max_value
        return value.to_u32
      end

      result = max_value.to_u32
      multiplier = 1_u32

      loop do
        byte = io.read_byte
        raise CompressionError.new("Unexpected end of data") unless byte

        # Check for overflow before addition
        increment = (byte & 0x7f).to_u32 * multiplier
        if result > UInt32::MAX - increment
          raise CompressionError.new("Integer overflow in decode_integer")
        end

        result += increment

        break if (byte & 0x80) == 0

        # Check multiplier overflow before multiplication
        if multiplier > UInt32::MAX // 128
          raise CompressionError.new("Multiplier overflow in decode_integer")
        end

        multiplier *= 128_u32
      end

      result
    end

    private def add_header_safely(headers : Headers, name : String, value : String) : Nil
      # Check header count limit
      if headers.size >= @security_limits.max_header_count
        raise HpackBombError.new("Header count exceeds limit: #{headers.size} >= #{@security_limits.max_header_count}")
      end

      # Calculate header size (name + value + 32 bytes overhead per RFC 7541)
      header_size = name.bytesize + value.bytesize + 32
      @total_decompressed_size += header_size

      # Check total decompressed size
      if @total_decompressed_size > @security_limits.max_decompressed_size
        raise HpackBombError.new("Total decompressed size exceeds limit: #{@total_decompressed_size} > #{@security_limits.max_decompressed_size}")
      end

      headers[name] = value
    end

    private def validate_final_headers(headers : Headers) : Nil
      # Final validation of total header count
      if headers.size > @security_limits.max_header_count
        raise HpackBombError.new("Final header count exceeds limit: #{headers.size}")
      end

      # Final validation of total decompressed size
      if @total_decompressed_size > @security_limits.max_decompressed_size
        raise HpackBombError.new("Final decompressed size exceeds limit: #{@total_decompressed_size}")
      end
    end
  end
end
