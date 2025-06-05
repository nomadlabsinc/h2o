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
      index = decode_integer(io, first_byte & 0x7f, 7)
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
      size = decode_integer(io, first_byte & 0x1f, 5)
      @dynamic_table.resize(size)
    end

    private def decode_literal_header(io : IO, name_index : UInt8, prefix_bits : Int32) : {String, String}
      if name_index == 0
        name = decode_string(io)
      else
        index = decode_integer(io, name_index, prefix_bits)
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
      length = decode_integer(io, first_byte & 0x7f, 7)

      data = Bytes.new(length)
      bytes_read = io.read(data)
      raise CompressionError.new("Unexpected end of data") if bytes_read != length

      if huffman_encoded
        Huffman.decode(data)
      else
        String.new(data)
      end
    end

    private def decode_integer(io : IO, value : UInt8, prefix_bits : Int32) : Int32
      max_value = (1 << prefix_bits) - 1

      if value < max_value
        return value.to_i32
      end

      result = max_value
      multiplier = 1

      loop do
        byte = io.read_byte
        raise CompressionError.new("Unexpected end of data") unless byte

        result += (byte & 0x7f) * multiplier

        break if (byte & 0x80) == 0

        multiplier *= 128
        raise CompressionError.new("Integer overflow") if multiplier > 0x1000000
      end

      result
    end
  end
end
