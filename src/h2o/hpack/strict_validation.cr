module H2O::HPACK
  # Strict HPACK validation following Go net/http2 and Rust h2 patterns
  # Based on RFC 7541 and security best practices
  module StrictValidation
    # Maximum allowed header list size (32KB default, configurable)
    DEFAULT_MAX_HEADER_LIST_SIZE = 32768

    # Maximum number of headers to prevent DoS
    MAX_HEADER_COUNT = 100

    # Maximum individual header name/value length
    MAX_HEADER_NAME_LENGTH  = 8192
    MAX_HEADER_VALUE_LENGTH = 8192

    # Dynamic table size limits
    MAX_DYNAMIC_TABLE_SIZE = 65536
    MIN_DYNAMIC_TABLE_SIZE =     0

    # Validate header name according to RFC 7541 and HTTP/2 requirements
    def self.validate_header_name(name : String) : Nil
      if name.empty?
        raise CompressionError.new("Header name cannot be empty")
      end

      if name.bytesize > MAX_HEADER_NAME_LENGTH
        raise CompressionError.new("Header name too long: #{name.bytesize} bytes")
      end

      # RFC 7230 Section 3.2.6: Header names must be tokens
      name.each_byte do |byte|
        unless valid_header_name_byte?(byte)
          raise CompressionError.new("Invalid character in header name: #{byte.chr} (0x#{byte.to_s(16)})")
        end
      end

      # HTTP/2 specific: header names must be lowercase
      name.each_char do |char|
        if char >= 'A' && char <= 'Z'
          raise CompressionError.new("Header name must be lowercase: #{name}")
        end
      end
    end

    # Validate header value according to RFC 7541 requirements
    def self.validate_header_value(value : String) : Nil
      if value.bytesize > MAX_HEADER_VALUE_LENGTH
        raise CompressionError.new("Header value too long: #{value.bytesize} bytes")
      end

      # RFC 7230 Section 3.2: No control characters except HTAB
      value.each_byte do |byte|
        unless valid_header_value_byte?(byte)
          raise CompressionError.new("Invalid character in header value: 0x#{byte.to_s(16)}")
        end
      end
    end

    # Validate complete header list size and count
    def self.validate_header_list(headers : Headers, max_size : Int32 = DEFAULT_MAX_HEADER_LIST_SIZE) : Nil
      if headers.size > MAX_HEADER_COUNT
        raise CompressionError.new("Too many headers: #{headers.size} > #{MAX_HEADER_COUNT}")
      end

      total_size = calculate_header_list_size(headers)
      if total_size > max_size
        raise CompressionError.new("Header list too large: #{total_size} bytes > #{max_size}")
      end
    end

    # Validate dynamic table size update
    def self.validate_dynamic_table_size(new_size : UInt32, max_allowed : UInt32) : Nil
      if new_size > max_allowed
        raise CompressionError.new("Dynamic table size #{new_size} exceeds maximum #{max_allowed}")
      end

      if new_size > MAX_DYNAMIC_TABLE_SIZE
        raise CompressionError.new("Dynamic table size #{new_size} exceeds absolute maximum #{MAX_DYNAMIC_TABLE_SIZE}")
      end
    end

    # Validate HPACK index bounds
    def self.validate_index(index : Int32, table_size : Int32) : Nil
      if index <= 0
        raise CompressionError.new("Invalid HPACK index: #{index} (must be > 0)")
      end

      if index > table_size
        raise CompressionError.new("HPACK index #{index} exceeds table size #{table_size}")
      end
    end

    # Validate string length before decoding
    def self.validate_string_length(length : UInt32, max_length : Int32) : Nil
      if length > max_length
        raise CompressionError.new("String length #{length} exceeds maximum #{max_length}")
      end

      if length > MAX_HEADER_NAME_LENGTH + MAX_HEADER_VALUE_LENGTH
        raise CompressionError.new("String length #{length} suspiciously large")
      end
    end

    # Validate compression ratio to detect HPACK bombs
    def self.validate_compression_ratio(compressed_size : Int32, decompressed_size : Int32, max_ratio : Float64 = 100.0) : Nil
      return if compressed_size == 0

      # Skip validation for very small payloads where high ratios are normal
      # For example, ":status: 200" is ~11 bytes compressed but ~42 bytes decompressed
      return if compressed_size < 50

      ratio = decompressed_size.to_f64 / compressed_size.to_f64
      if ratio > max_ratio
        raise HpackBombError.new("Suspicious compression ratio: #{ratio.round(2)} (#{decompressed_size}/#{compressed_size})")
      end
    end

    # Calculate header list size according to RFC 7541 Section 4.1
    def self.calculate_header_list_size(headers : Headers) : Int32
      size = 0
      headers.each do |name, value|
        # RFC 7541: size = name.length + value.length + 32
        size += name.bytesize + value.bytesize + 32
      end
      size
    end

    # Check if byte is valid in header name (RFC 7230 token characters)
    private def self.valid_header_name_byte?(byte : UInt8) : Bool
      case byte
      when 0x21, 0x23..0x27, 0x2a, 0x2b, 0x2d, 0x2e, 0x30..0x39, 0x3a, 0x41..0x5a, 0x5e..0x7a, 0x7c, 0x7e
        true
      else
        false
      end
    end

    # Check if byte is valid in header value (RFC 7230 field-content)
    private def self.valid_header_value_byte?(byte : UInt8) : Bool
      case byte
      when 0x09, 0x20..0x7e, 0x80..0xff # HTAB, VCHAR, obs-text
        true
      else
        false
      end
    end
  end
end
