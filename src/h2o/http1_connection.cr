require "./tls"

module H2O
  abstract class BaseConnection
    abstract def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response?
    abstract def close : Nil
    abstract def closed? : Bool
  end

  class Http1Connection < BaseConnection
    property socket : TlsSocket
    property closed : Bool

    def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds)
      @socket = TlsSocket.new(hostname, port, connect_timeout: connect_timeout)
      @closed = false
      validate_http1_connection
    end

    def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response?
      raise ConnectionError.new("Connection is closed") if @closed

      request_line = build_request_line(method, path)
      request_headers = build_http1_headers(headers, body)

      send_request(request_line, request_headers, body)
      parse_response
    end

    def close : Nil
      return if @closed
      @closed = true
      @socket.close
    end

    def closed? : Bool
      @closed || @socket.closed?
    end

    private def validate_http1_connection : Nil
      if @socket.negotiated_http2?
        raise ConnectionError.new("Expected HTTP/1.1 but got HTTP/2")
      end
    end

    private def build_request_line(method : String, path : String) : String
      "#{method} #{path} HTTP/1.1\r\n"
    end

    private def build_http1_headers(headers : Headers, body : String?) : String
      header_lines = String::Builder.new

      headers.each do |name, value|
        header_lines << "#{name}: #{value}\r\n"
      end

      if body && !headers.has_key?("content-length")
        header_lines << "Content-Length: #{body.bytesize}\r\n"
      end

      header_lines << "Connection: keep-alive\r\n"
      header_lines << "\r\n"
      header_lines.to_s
    end

    private def send_request(request_line : String, headers : String, body : String?) : Nil
      @socket.write(request_line.to_slice)
      @socket.write(headers.to_slice)

      if body
        @socket.write(body.to_slice)
      end

      @socket.flush
    end

    private def parse_response : Response?
      status_line = read_line
      return nil unless status_line

      status = parse_status_line(status_line)
      headers = parse_headers
      body = read_body(headers)

      Response.new(status, headers, body, "HTTP/1.1")
    end

    private def read_line : String?
      line = String::Builder.new

      loop do
        char_bytes = Bytes.new(1)
        bytes_read = @socket.read(char_bytes)
        return nil if bytes_read == 0

        char = char_bytes[0].chr

        if char == '\r'
          peek_bytes = Bytes.new(1)
          next_bytes = @socket.read(peek_bytes)
          if next_bytes > 0 && peek_bytes[0].chr == '\n'
            break
          else
            line << char
            line << peek_bytes[0].chr if next_bytes > 0
          end
        else
          line << char
        end
      end

      line.to_s
    end

    private def parse_status_line(status_line : String) : Int32
      parts = status_line.split(' ', 3)
      return 500 if parts.size < 2

      parts[1].to_i? || 500
    end

    private def parse_headers : Headers
      headers = Headers.new

      loop do
        line = read_line
        break if !line || line.empty?

        if colon_index = line.index(':')
          name = line[0...colon_index].strip.downcase
          value = line[colon_index + 1..-1].strip
          headers[name] = value
        end
      end

      headers
    end

    private def read_body(headers : Headers) : String
      content_length = headers["content-length"]?.try(&.to_i?) || 0

      if content_length > 0
        body_bytes = Bytes.new(content_length)
        bytes_read = @socket.read(body_bytes)
        String.new(body_bytes[0, bytes_read])
      else
        ""
      end
    end
  end
end
