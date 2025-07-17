require "./hpack/decoder"
require "./frames/headers_frame"
require "./frames/data_frame"

module H2O
  # Assembles HTTP/2 frames into complete HTTP responses
  # Maintains stateful frame accumulation until response completion
  class ResponseTranslator
    @hpack_decoder : HPACK::Decoder
    @response_headers : Headers
    @response_body : IO::Memory
    @status_code : Int32
    @headers_complete : Bool
    @data_complete : Bool

    def initialize(@hpack_decoder : HPACK::Decoder)
      @response_headers = Headers.new
      @response_body = IO::Memory.new
      @status_code = 0
      @headers_complete = false
      @data_complete = false
    end

    def process_headers_frame(frame : HeadersFrame) : Nil
      validate_headers_frame(frame)

      decoded_headers = @hpack_decoder.decode(frame.header_block)
      process_decoded_headers(decoded_headers)
      @headers_complete = frame.end_headers?
      @data_complete = frame.end_stream?
    end

    def process_data_frame(frame : DataFrame) : Nil
      validate_data_frame(frame)

      @response_body.write(frame.data)
      @data_complete = frame.end_stream?
    end

    def response_complete? : Bool
      @headers_complete && @data_complete
    end

    # Only callable when both headers and data are complete
    def build_response : Response
      unless response_complete?
        raise ArgumentError.new("Response is not complete - cannot build Response object")
      end

      if @status_code == 0
        raise ArgumentError.new("Missing :status pseudo-header in response")
      end

      Response.new(
        status: @status_code,
        headers: @response_headers.dup,
        body: @response_body.to_s,
        protocol: "HTTP/2"
      )
    end

    # Allows single translator instance to process multiple responses
    def reset : Nil
      @response_headers.clear
      @response_body = IO::Memory.new
      @status_code = 0
      @headers_complete = false
      @data_complete = false
    end

    def status : Int32
      @status_code
    end

    def headers : Headers
      @response_headers
    end

    def body : String
      @response_body.to_s
    end

    def headers_complete? : Bool
      @headers_complete
    end

    def data_complete? : Bool
      @data_complete
    end

    # Convenience method for processing frame arrays
    def self.translate_frames(frames : Array(Frame), decoder : HPACK::Decoder) : Response
      translator = new(decoder)

      frames.each do |frame|
        case frame
        when HeadersFrame
          translator.process_headers_frame(frame)
        when DataFrame
          translator.process_data_frame(frame)
        else
        end
      end

      translator.build_response
    end

    # Separates headers and data for clearer frame type handling
    def self.translate_stream_frames(headers_frames : Array(HeadersFrame),
                                     data_frames : Array(DataFrame),
                                     decoder : HPACK::Decoder) : Response
      translator = new(decoder)

      headers_frames.each do |frame|
        translator.process_headers_frame(frame)
      end

      data_frames.each do |frame|
        translator.process_data_frame(frame)
      end

      translator.build_response
    end

    # Status pseudo-header extraction required by HTTP/2 spec
    private def process_decoded_headers(decoded_headers : Headers) : Nil
      decoded_headers.each do |name, value|
        if name == ":status"
          @status_code = parse_status_code(value)
        else
          unless name.starts_with?(":")
            @response_headers[name] = value
          end
        end
      end
    end

    # HTTP status codes must be in 100-599 range
    private def parse_status_code(status_value : String) : Int32
      status_code = status_value.to_i?
      if status_code.nil? || status_code < 100 || status_code > 599
        raise ArgumentError.new("Invalid :status pseudo-header value: #{status_value}")
      end
      status_code
    end

    # Empty header blocks violate HTTP/2 protocol
    private def validate_headers_frame(frame : HeadersFrame) : Nil
      if frame.header_block.empty?
        raise ArgumentError.new("HEADERS frame cannot have empty header block")
      end
    end

    # DATA frames may be empty for flow control purposes
    private def validate_data_frame(frame : DataFrame) : Nil
    end

    # Factory method for protocol error responses
    def self.create_error_response(error_message : String, status_code : Int32 = 500) : Response
      Response.new(
        status: status_code,
        headers: Headers.new,
        body: error_message,
        protocol: "HTTP/2"
      )
    end

    # Ensures response meets HTTP/2 requirements before completion
    def validate_response : Nil
      unless @headers_complete
        raise ArgumentError.new("Response headers are not complete")
      end

      if @status_code == 0
        raise ArgumentError.new("Missing :status pseudo-header")
      end
    end

    # Diagnostic information for debugging and monitoring
    def statistics : Hash(Symbol, Int32 | Bool)
      {
        :status_code      => @status_code,
        :headers_count    => @response_headers.size,
        :body_size        => @response_body.size,
        :headers_complete => @headers_complete,
        :data_complete    => @data_complete,
        :response_ready   => response_complete?,
      }
    end
  end
end
