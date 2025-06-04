module H2O::HPACK
  class Encoder
    property dynamic_table : DynamicTable
    property huffman_encoding : Bool

    def initialize(table_size : Int32 = DynamicTable::DEFAULT_SIZE, @huffman_encoding : Bool = true)
      @dynamic_table = DynamicTable.new(table_size)
    end

    def encode(headers : Headers) : Bytes
      result = IO::Memory.new

      headers.each do |name, value|
        encode_header(result, name, value)
      end

      result.to_slice
    end

    def dynamic_table_size=(size : Int32) : Bytes
      @dynamic_table.resize(size)
      encode_table_size_update(size)
    end

    private def encode_header(io : IO, name : String, value : String) : Nil
      index = @dynamic_table.find_name_value(name, value)

      if index
        encode_indexed_header(io, index)
      else
        name_index = @dynamic_table.find_name(name)

        if should_index?(name, value)
          if name_index
            encode_literal_with_incremental_indexing_indexed_name(io, name_index, value)
          else
            encode_literal_with_incremental_indexing_new_name(io, name, value)
          end
          @dynamic_table.add(name, value)
        else
          if name_index
            encode_literal_without_indexing_indexed_name(io, name_index, value)
          else
            encode_literal_without_indexing_new_name(io, name, value)
          end
        end
      end
    end

    private def encode_indexed_header(io : IO, index : Int32) : Nil
      encode_integer(io, index, 7, 0x80_u8)
    end

    private def encode_literal_with_incremental_indexing_indexed_name(io : IO, index : Int32, value : String) : Nil
      encode_integer(io, index, 6, 0x40_u8)
      encode_string(io, value)
    end

    private def encode_literal_with_incremental_indexing_new_name(io : IO, name : String, value : String) : Nil
      io.write_byte(0x40_u8)
      encode_string(io, name)
      encode_string(io, value)
    end

    private def encode_literal_without_indexing_indexed_name(io : IO, index : Int32, value : String) : Nil
      encode_integer(io, index, 4, 0x00_u8)
      encode_string(io, value)
    end

    private def encode_literal_without_indexing_new_name(io : IO, name : String, value : String) : Nil
      io.write_byte(0x00_u8)
      encode_string(io, name)
      encode_string(io, value)
    end

    private def encode_string(io : IO, string : String) : Nil
      if @huffman_encoding
        encoded = Huffman.encode(string)
        encode_integer(io, encoded.size, 7, 0x80_u8)
        io.write(encoded)
      else
        encode_integer(io, string.bytesize, 7, 0x00_u8)
        io.write(string.to_slice)
      end
    end

    private def encode_integer(io : IO, value : Int32, prefix_bits : Int32, pattern : UInt8) : Nil
      max_value = (1 << prefix_bits) - 1

      if value < max_value
        io.write_byte(pattern | value.to_u8)
      else
        io.write_byte(pattern | max_value.to_u8)
        value -= max_value

        while value >= 128
          io.write_byte(((value % 128) + 128).to_u8)
          value //= 128
        end

        io.write_byte(value.to_u8)
      end
    end

    private def encode_table_size_update(size : Int32) : Bytes
      result = IO::Memory.new
      encode_integer(result, size, 4, 0x20_u8)
      result.to_slice
    end

    private def should_index?(name : String, value : String) : Bool
      return false if name.starts_with?(":")
      return false if name == "authorization"
      return false if name == "cookie"
      return false if name == "set-cookie"
      return false if value.bytesize > 1024
      true
    end
  end
end
