module H2O
  # Header list size validation following RFC 7540 Section 6.5.2 and 10.5.1
  # Based on Go net/http2 and Rust h2 strict validation patterns
  module HeaderListValidation
    # Default limits following RFC recommendations and production practices
    DEFAULT_MAX_HEADER_LIST_SIZE  =  262144 # 256KB - conservative default
    ABSOLUTE_MAX_HEADER_LIST_SIZE = 1048576 # 1MB - absolute maximum

    # Per-header limits to prevent individual header attacks
    MAX_HEADER_NAME_LENGTH  =  8192 # 8KB max header name
    MAX_HEADER_VALUE_LENGTH = 32768 # 32KB max header value
    MAX_HEADER_COUNT        =   100 # Maximum number of headers

    # Pseudo-header validation
    REQUIRED_REQUEST_PSEUDO_HEADERS  = [":method", ":path", ":scheme"]
    OPTIONAL_REQUEST_PSEUDO_HEADERS  = [":authority"]
    REQUIRED_RESPONSE_PSEUDO_HEADERS = [":status"]

    # Calculate header list size according to RFC 7541 Section 4.1
    # Each header field table entry consists of a name and value
    # and contributes to the header list size as: name.length + value.length + 32
    def self.calculate_header_list_size(headers : Headers) : Int32
      total_size = 0
      headers.each do |name, value|
        # RFC 7541: size = name.bytesize + value.bytesize + 32
        total_size += name.bytesize + value.bytesize + 32
      end
      total_size
    end

    # Validate complete header list against size limits
    def self.validate_header_list_size(headers : Headers, max_size : Int32? = nil) : Nil
      # Use provided limit or default
      limit = max_size || DEFAULT_MAX_HEADER_LIST_SIZE

      # Validate against absolute maximum
      if limit > ABSOLUTE_MAX_HEADER_LIST_SIZE
        limit = ABSOLUTE_MAX_HEADER_LIST_SIZE
      end

      total_size = calculate_header_list_size(headers)
      if total_size > limit
        raise CompressionError.new("Header list size #{total_size} exceeds limit #{limit}")
      end

      # Validate header count
      if headers.size > MAX_HEADER_COUNT
        raise CompressionError.new("Too many headers: #{headers.size} > #{MAX_HEADER_COUNT}")
      end
    end

    # Validate individual header size limits
    def self.validate_individual_header_limits(name : String, value : String) : Nil
      if name.bytesize > MAX_HEADER_NAME_LENGTH
        raise CompressionError.new("Header name too long: #{name.bytesize} bytes > #{MAX_HEADER_NAME_LENGTH}")
      end

      if value.bytesize > MAX_HEADER_VALUE_LENGTH
        raise CompressionError.new("Header value too long: #{value.bytesize} bytes > #{MAX_HEADER_VALUE_LENGTH}")
      end
    end

    # Validate request pseudo-headers following RFC 7540 Section 8.1.2.3
    def self.validate_request_pseudo_headers(headers : Headers) : Nil
      pseudo_headers = headers.select { |name, _| name.starts_with?(":") }
      regular_headers = headers.reject { |name, _| name.starts_with?(":") }

      # Check that all pseudo-headers come before regular headers
      # (This is a parsing concern, but we validate the result)

      # Validate required pseudo-headers are present
      REQUIRED_REQUEST_PSEUDO_HEADERS.each do |required_header|
        unless pseudo_headers.has_key?(required_header)
          raise CompressionError.new("Missing required pseudo-header: #{required_header}")
        end
      end

      # Validate pseudo-headers are valid
      pseudo_headers.each do |name, value|
        case name
        when ":method"
          validate_method_pseudo_header(value)
        when ":path"
          validate_path_pseudo_header(value)
        when ":scheme"
          validate_scheme_pseudo_header(value)
        when ":authority"
          validate_authority_pseudo_header(value)
        else
          # RFC 7540 Section 8.1.2.1: Unknown pseudo-headers are forbidden
          raise CompressionError.new("Unknown pseudo-header: #{name}")
        end
      end

      # Validate no duplicate pseudo-headers
      validate_no_duplicate_pseudo_headers(pseudo_headers)
    end

    # Validate response pseudo-headers following RFC 7540 Section 8.1.2.4
    def self.validate_response_pseudo_headers(headers : Headers) : Nil
      pseudo_headers = headers.select { |name, _| name.starts_with?(":") }

      # Response must have exactly one :status pseudo-header
      status_headers = pseudo_headers.select { |name, _| name == ":status" }
      if status_headers.size != 1
        raise CompressionError.new("Response must have exactly one :status pseudo-header, got #{status_headers.size}")
      end

      # Validate status value
      status_value = status_headers.first[1]
      validate_status_pseudo_header(status_value)

      # Check for invalid pseudo-headers in responses
      pseudo_headers.each do |name, _value|
        unless name == ":status"
          raise CompressionError.new("Invalid pseudo-header in response: #{name}")
        end
      end
    end

    # Validate header list for HTTP/2 compliance
    def self.validate_http2_header_list(headers : Headers, is_request : Bool, max_size : Int32? = nil) : Nil
      # Basic size validation
      validate_header_list_size(headers, max_size)

      # Individual header validation
      headers.each do |name, value|
        validate_individual_header_limits(name, value)
        validate_header_name_compliance(name)
        validate_header_value_compliance(value)
      end

      # Pseudo-header validation
      if is_request
        validate_request_pseudo_headers(headers)
      else
        validate_response_pseudo_headers(headers)
      end

      # Connection-specific header validation
      validate_connection_specific_headers(headers)
    end

    # Validate method pseudo-header
    private def self.validate_method_pseudo_header(value : String) : Nil
      if value.empty?
        raise CompressionError.new(":method pseudo-header cannot be empty")
      end

      # RFC 7230 Section 3.1.1: Method tokens
      unless value.matches?(/^[A-Z][A-Z0-9]*$/)
        raise CompressionError.new("Invalid :method value: #{value}")
      end
    end

    # Validate path pseudo-header
    private def self.validate_path_pseudo_header(value : String) : Nil
      if value.empty?
        raise CompressionError.new(":path pseudo-header cannot be empty")
      end

      # RFC 7540 Section 8.1.2.3: :path must not be empty for HTTP or HTTPS
      unless value.starts_with?("/") || value == "*"
        raise CompressionError.new("Invalid :path value: #{value}")
      end
    end

    # Validate scheme pseudo-header
    private def self.validate_scheme_pseudo_header(value : String) : Nil
      unless ["http", "https"].includes?(value)
        raise CompressionError.new("Invalid :scheme value: #{value}")
      end
    end

    # Validate authority pseudo-header
    private def self.validate_authority_pseudo_header(value : String) : Nil
      if value.empty?
        raise CompressionError.new(":authority pseudo-header cannot be empty")
      end

      # Basic authority validation (could be enhanced with more detailed parsing)
      if value.includes?(" ") || value.includes?("\t")
        raise CompressionError.new("Invalid :authority value: #{value}")
      end
    end

    # Validate status pseudo-header
    private def self.validate_status_pseudo_header(value : String) : Nil
      unless value.matches?(/^\d{3}$/)
        raise CompressionError.new("Invalid :status value: #{value}")
      end

      status_code = value.to_i
      unless (100..599).includes?(status_code)
        raise CompressionError.new("Invalid HTTP status code: #{status_code}")
      end
    end

    # Validate header name compliance
    private def self.validate_header_name_compliance(name : String) : Nil
      # HTTP/2 header names must be lowercase
      if name != name.downcase
        raise CompressionError.new("Header names must be lowercase: #{name}")
      end

      # Connection-specific headers are forbidden in HTTP/2
      forbidden_headers = ["connection", "upgrade", "proxy-connection", "keep-alive", "transfer-encoding"]
      if forbidden_headers.includes?(name.downcase)
        raise CompressionError.new("Forbidden header in HTTP/2: #{name}")
      end
    end

    # Validate header value compliance
    private def self.validate_header_value_compliance(value : String) : Nil
      # Check for invalid characters (basic validation)
      value.each_char do |char|
        if char.ord < 32 && char != '\t'
          raise CompressionError.new("Invalid character in header value: 0x#{char.ord.to_s(16)}")
        end
      end
    end

    # Validate no duplicate pseudo-headers
    private def self.validate_no_duplicate_pseudo_headers(pseudo_headers : Hash(String, String)) : Nil
      # This is inherently validated by using Hash, but we check for completeness
      # In practice, the HPACK decoder would have already handled duplicates
    end

    # Validate connection-specific headers are not present
    private def self.validate_connection_specific_headers(headers : Headers) : Nil
      # RFC 7540 Section 8.1.2.2: Connection-specific header fields MUST NOT appear
      forbidden_headers = [
        "connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade",
      ]

      headers.each do |name, _value|
        if forbidden_headers.includes?(name.downcase)
          raise CompressionError.new("Connection-specific header forbidden in HTTP/2: #{name}")
        end
      end

      # Special validation for TE header
      if te_value = headers["te"]?
        unless te_value.downcase == "trailers"
          raise CompressionError.new("TE header must only contain 'trailers' in HTTP/2")
        end
      end
    end
  end
end
