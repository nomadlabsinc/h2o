require "./strict_validation"
require "../header_list_validation"

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
      # Strict validation: Check input size limits
      if data.size > @security_limits.max_decompressed_size
        raise CompressionError.new("Compressed data too large: #{data.size} bytes")
      end

      headers = Headers.new
      io = IO::Memory.new(data)
      @total_decompressed_size = 0
      header_count = 0

      while io.pos < io.size
        # Prevent excessive header count during decoding
        if header_count >= StrictValidation::MAX_HEADER_COUNT
          raise CompressionError.new("Too many headers during decoding: #{header_count}")
        end

        decode_header(io, headers)
        header_count += 1
      end

      # Strict final validation
      validate_final_headers_strict(headers, data.size)
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
        Log.debug { "Header index too large: #{index_raw}" }
        raise CompressionError.new("Header index too large: #{index_raw}")
      end
      index = index_raw.to_i32

      # Special handling for index 0 (invalid) and out-of-bounds indices
      if index == 0
        Log.debug { "Invalid header index: 0 (reserved)" }
        raise CompressionError.new("Invalid header index: #{index}")
      end

      entry = @dynamic_table[index]

      unless entry
        Log.debug { "Invalid header index: #{index} (out of bounds, table size: #{@dynamic_table.size})" }
        raise CompressionError.new("Invalid header index: #{index}")
      end

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

      # Strict validation of dynamic table size
      StrictValidation.validate_dynamic_table_size(size_raw, @security_limits.max_dynamic_table_size.to_u32)

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
      unless first_byte
        Log.debug { "Unexpected end of data while reading string length byte" }
        raise CompressionError.new("Unexpected end of data")
      end

      huffman_encoded = (first_byte & 0x80) != 0
      length_raw = decode_integer(io, first_byte & 0x7f, 7)

      # Convert UInt32 to Int32 with bounds checking for string length
      if length_raw > Int32::MAX
        Log.debug { "String length too large: #{length_raw}" }
        raise CompressionError.new("String length too large: #{length_raw}")
      end
      length = length_raw.to_i32

      # Strict validation of string length
      StrictValidation.validate_string_length(length_raw, @security_limits.max_string_length)

      # Don't use BufferPool to avoid memory corruption
      data = Bytes.new(length)
      bytes_read = io.read(data)
      if bytes_read != length
        Log.debug { "Unexpected end of data while reading string: expected #{length} bytes, got #{bytes_read}" }
        raise CompressionError.new("Unexpected end of data")
      end

      if huffman_encoded
        Huffman.decode(data, @security_limits.max_string_length)
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

    private def add_header_safely(headers : Headers, name : String, value : String) : Nil
      # Strict validation of header name and value
      StrictValidation.validate_header_name(name)
      StrictValidation.validate_header_value(value)

      # Check header count limit
      if headers.size >= @security_limits.max_header_count
        raise CompressionError.new("Header count exceeds limit: #{headers.size} >= #{@security_limits.max_header_count}")
      end

      # Calculate header size (name + value + 32 bytes overhead per RFC 7541)
      header_size = name.bytesize + value.bytesize + 32
      @total_decompressed_size += header_size

      # Check total decompressed size
      if @total_decompressed_size > @security_limits.max_decompressed_size
        raise CompressionError.new("Total decompressed size exceeds limit: #{@total_decompressed_size} > #{@security_limits.max_decompressed_size}")
      end

      headers[name] = value
    end

    private def validate_final_headers(headers : Headers) : Nil
      # Final validation of total header count
      if headers.size > @security_limits.max_header_count
        raise CompressionError.new("Final header count exceeds limit: #{headers.size}")
      end

      # Final validation of total decompressed size
      if @total_decompressed_size > @security_limits.max_decompressed_size
        raise CompressionError.new("Final decompressed size exceeds limit: #{@total_decompressed_size}")
      end
    end

    # Enhanced strict validation following Go net/http2 and Rust h2 patterns
    private def validate_final_headers_strict(headers : Headers, compressed_size : Int32) : Nil
      # Use strict validation module
      StrictValidation.validate_header_list(headers, @security_limits.max_decompressed_size)

      # Enhanced header list size validation
      HeaderListValidation.validate_header_list_size(headers, @security_limits.max_decompressed_size)

      # Check compression ratio for HPACK bomb detection
      StrictValidation.validate_compression_ratio(compressed_size, @total_decompressed_size, @security_limits.compression_ratio_limit)

      # Validate each header name/value pair for compliance
      headers.each do |name, value|
        StrictValidation.validate_header_name(name)
        StrictValidation.validate_header_value(value)
        HeaderListValidation.validate_individual_header_limits(name, value)
      end
    end
  end
end
