require "./hpack/encoder"
require "./frames/headers_frame"
require "./frames/data_frame"

module H2O
  # Separates HTTP semantics from HTTP/2 framing concerns
  # Encapsulates pseudo-header rules and HPACK encoding complexity
  class RequestTranslator
    @hpack_encoder : HPACK::Encoder

    def initialize(@hpack_encoder : HPACK::Encoder)
    end

    def translate(request : Request, stream_id : StreamId) : {HeadersFrame, DataFrame?}
      request_headers = build_request_headers(request)
      encoded_headers = @hpack_encoder.encode(request_headers)
      headers_frame = create_headers_frame(stream_id, encoded_headers, request.body.nil?)
      data_frame = request.body ? create_data_frame(stream_id, request.body.as(String)) : nil

      {headers_frame, data_frame}
    end

    # HTTP/2 requires pseudo-headers first, followed by regular headers
    private def build_request_headers(request : Request) : Headers
      method = request.method
      path = request.path
      host = extract_host_header(request.headers)

      request_headers = Headers.new
      request_headers[":method"] = method
      request_headers[":path"] = path
      request_headers[":scheme"] = "https"
      request_headers[":authority"] = host
      request.headers.each do |name, value|
        unless name.downcase == "host"
          request_headers[name.downcase] = value
        end
      end

      request_headers
    end

    # Host header becomes :authority pseudo-header in HTTP/2
    private def extract_host_header(headers : Headers) : String
      host = headers["host"]? || headers["Host"]?
      if host.nil? || host.empty?
        raise ArgumentError.new("Missing host header - required for HTTP/2 :authority pseudo-header")
      end
      host
    end

    # END_STREAM flag when no body, END_HEADERS always set for single frame
    private def create_headers_frame(stream_id : StreamId, encoded_headers : Bytes, end_stream : Bool) : HeadersFrame
      flags = end_stream ? HeadersFrame::FLAG_END_STREAM | HeadersFrame::FLAG_END_HEADERS : HeadersFrame::FLAG_END_HEADERS

      HeadersFrame.new(
        stream_id: stream_id,
        header_block: encoded_headers,
        flags: flags,
        priority_exclusive: false,
        priority_dependency: 0_u32,
        priority_weight: 0_u8
      )
    end

    # Always set END_STREAM on final DATA frame
    private def create_data_frame(stream_id : StreamId, body : String) : DataFrame
      DataFrame.new(
        stream_id: stream_id,
        data: body.to_slice,
        flags: DataFrame::FLAG_END_STREAM
      )
    end

    # Direct frame creation bypassing Request object structure
    def create_headers_frame(stream_id : StreamId, method : String, path : String,
                             headers : Headers, body : String?) : HeadersFrame
      request_headers = Headers.new
      request_headers[":method"] = method
      request_headers[":path"] = path
      request_headers[":scheme"] = "https"

      authority = headers.delete("host") || headers.delete("Host")
      if authority.nil? || authority.empty?
        raise ArgumentError.new("Missing host header")
      end
      request_headers[":authority"] = authority

      headers.each { |k, v| request_headers[k.downcase] = v }
      encoded_headers = @hpack_encoder.encode(request_headers)
      flags = body.nil? ? HeadersFrame::FLAG_END_STREAM | HeadersFrame::FLAG_END_HEADERS : HeadersFrame::FLAG_END_HEADERS

      HeadersFrame.new(
        stream_id: stream_id,
        header_block: encoded_headers,
        flags: flags,
        priority_exclusive: false,
        priority_dependency: 0_u32,
        priority_weight: 0_u8
      )
    end

    def create_data_frame(stream_id : StreamId, body : String) : DataFrame
      DataFrame.new(
        stream_id: stream_id,
        data: body.to_slice,
        flags: DataFrame::FLAG_END_STREAM
      )
    end

    # Prevents invalid frames that violate HTTP/2 protocol
    def validate_request(request : Request) : Nil
      if request.method.empty?
        raise ArgumentError.new("Request method cannot be empty")
      end

      if request.path.empty?
        raise ArgumentError.new("Request path cannot be empty")
      end

      extract_host_header(request.headers)

      unless valid_http_method?(request.method)
        raise ArgumentError.new("Invalid HTTP method: #{request.method}")
      end
      unless valid_http_path?(request.path)
        raise ArgumentError.new("Invalid HTTP path: #{request.path}")
      end
    end

    private def valid_http_method?(method : String) : Bool
      %w[GET POST PUT DELETE HEAD OPTIONS PATCH TRACE CONNECT].includes?(method.upcase)
    end

    # Asterisk form only valid for OPTIONS requests
    private def valid_http_path?(path : String) : Bool
      path.starts_with?("/") || path == "*"
    end
  end
end
