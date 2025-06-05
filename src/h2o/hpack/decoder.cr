module H2O::HPACK
  class Decoder
    property dynamic_table : DynamicTable

    def initialize(table_size : Int32 = DynamicTable::DEFAULT_SIZE)
      @dynamic_table = DynamicTable.new(table_size)
    end

    def decode(data : Bytes) : Headers
      headers = Headers.new
      io = IO::Memory.new(data)

      while io.pos < io.size
        decode_header(io, headers)
      end

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

      headers[entry.name] = entry.value
    end

    private def decode_literal_with_incremental_indexing(io : IO, headers : Headers, first_byte : UInt8) : Nil
      name, value = decode_literal_header(io, first_byte & 0x3f, 6)
      headers[name] = value
      @dynamic_table.add(name, value)
    end

    private def decode_literal_without_indexing(io : IO, headers : Headers, first_byte : UInt8) : Nil
      name, value = decode_literal_header(io, first_byte & 0x0f, 4)
      headers[name] = value
    end

    private def decode_dynamic_table_size_update(io : IO, first_byte : UInt8) : Nil
      size_raw = decode_integer(io, first_byte & 0x1f, 5)

      # Convert UInt32 to Int32 with bounds checking
      if size_raw > Int32::MAX
        raise CompressionError.new("Dynamic table size too large: #{size_raw}")
      end
      size = size_raw.to_i32

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

      data = Bytes.new(length)
      bytes_read = io.read(data)
      raise CompressionError.new("Unexpected end of data") if bytes_read != length

      if huffman_encoded
        Huffman.decode(data)
      else
        String.new(data)
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
  end
end
