require "log"
require "../types"
require "../exceptions"
require "../http1_connection"
require "../tls"
require "../tcp_socket"
require "../preface"
require "../hpack/encoder"
require "../hpack/decoder"
require "../frames/frame"
require "../frames/headers_frame"
require "../frames/data_frame"
require "../frames/settings_frame"
require "../frames/rst_stream_frame"
require "../frames/goaway_frame"
require "../frames/ping_frame"
require "../frames/window_update_frame"

module H2O
  module H2
    Log = ::Log.for("h2o.h2")
    
    # Simplified HTTP/2 client without multiplexing
    # Each client handles one request at a time
    class Client < BaseConnection
      property socket : TlsSocket | TcpSocket
      property local_settings : Settings
      property remote_settings : Settings
      property hpack_encoder : HPACK::Encoder
      property hpack_decoder : HPACK::Decoder
      property connection_window_size : Int32
      property closed : Bool
      property closing : Bool = false
      property request_timeout : Time::Span
      property connect_timeout : Time::Span
      
      # Single mutex for all operations
      property mutex : Mutex
      
      # Current stream ID (odd numbers for client-initiated streams)
      property current_stream_id : StreamId
      
      def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds, request_timeout : Time::Span = 5.seconds, verify_ssl : Bool = true, use_tls : Bool = true)
        if use_tls
          verify_mode : OpenSSL::SSL::VerifyMode = verify_ssl ? OpenSSL::SSL::VerifyMode::PEER : OpenSSL::SSL::VerifyMode::NONE
          Log.debug { "Creating H2::Client for #{hostname}:#{port} with TLS and verify_mode=#{verify_mode}" }
          @socket = TlsSocket.new(hostname, port, verify_mode: verify_mode, connect_timeout: connect_timeout)
          Log.debug { "TLS connection established for #{hostname}:#{port}" }
          validate_http2_negotiation
        else
          Log.debug { "Creating H2::Client for #{hostname}:#{port} with prior knowledge (no TLS)" }
          @socket = TcpSocket.new(hostname, port, connect_timeout: connect_timeout)
          Log.debug { "TCP connection established for #{hostname}:#{port}" }
        end

        @local_settings = Settings.new
        @remote_settings = Settings.new
        @hpack_encoder = HPACK::Encoder.new
        @hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
        @connection_window_size = 65535
        @current_stream_id = 1_u32
        @closed = false
        @request_timeout = request_timeout
        @connect_timeout = connect_timeout
        @mutex = Mutex.new

        # Send initial preface and settings
        send_initial_preface
        
        # Wait for server settings
        unless validate_server_preface
          raise ConnectionError.new("Failed to receive valid server preface")
        end
      end

      # Test-only initializer for injecting a mock IO
      {% if flag?(:test) %}
        def initialize(@socket : IO, connect_timeout : Time::Span = 5.seconds, request_timeout : Time::Span = 5.seconds)
          @local_settings = Settings.new
          @remote_settings = Settings.new
          @hpack_encoder = HPACK::Encoder.new
          @hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
          @connection_window_size = 65535
          @current_stream_id = 1_u32
          @closed = false
          @request_timeout = request_timeout
          @connect_timeout = connect_timeout
          @mutex = Mutex.new
        end
      {% end %}

      def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        return Response.error(0, "Connection is closed", "HTTP/2") if @closed

        # Use a timeout for the entire request
        start_time = Time.monotonic
        
        begin
          # Synchronize the request sending and response reading
          @mutex.synchronize do
            # Check timeout before starting
            if Time.monotonic - start_time > @request_timeout
              return Response.error(0, "Request timeout", "HTTP/2")
            end

            # Use the next odd stream ID
            stream_id = @current_stream_id
            @current_stream_id += 2

            # Send request
            send_request(stream_id, method, path, headers, body)

            # Read response with timeout checking
            read_response_with_timeout(stream_id, start_time)
          end
        rescue ex : Exception
          Log.error { "Request failed: #{ex.message}" }
          Response.error(0, ex.message || "Unknown error", "HTTP/2")
        end
      end

      def close : Nil
        @mutex.synchronize do
          return if @closed
          @closed = true

          begin
            # Send GOAWAY frame
            goaway_frame = GoawayFrame.new(@current_stream_id - 2, ErrorCode::NoError)
            write_frame(goaway_frame)
          rescue
            # Best effort
          end

          @socket.close rescue nil
        end
      end

      def closed? : Bool
        @closed
      end

      private def send_initial_preface : Nil
        # Send the HTTP/2 connection preface
        Preface.send_preface(@socket.to_io)

        # Send initial SETTINGS frame
        initial_settings = Preface.create_initial_settings
        write_frame(initial_settings)

        Log.debug { "Sent HTTP/2 connection preface and initial SETTINGS" }
      rescue ex : IO::Error
        Log.debug { "Failed to send initial preface: #{ex.message}" }
        raise ex
      end

      private def validate_server_preface : Bool
        # Read the first frame - must be SETTINGS
        frame = read_frame
        return false unless frame.is_a?(SettingsFrame)

        # Process server settings
        handle_settings_frame(frame)
        
        # Send SETTINGS ACK
        settings_ack = SettingsFrame.new(ack: true)
        write_frame(settings_ack)

        true
      rescue ex
        Log.error { "Failed to validate server preface: #{ex.message}" }
        false
      end

      private def validate_http2_negotiation : Nil
        # Only validate ALPN negotiation for TLS sockets
        if socket = @socket.as?(TlsSocket)
          unless socket.negotiated_http2?
            raise ConnectionError.new("HTTP/2 not negotiated via ALPN")
          end
        end
      end

      private def send_request(stream_id : StreamId, method : String, path : String, headers : Headers, body : String?) : Nil
        # Build request headers
        request_headers = Headers.new
        request_headers[":method"] = method
        request_headers[":path"] = path
        request_headers[":scheme"] = "https"
        
        # Extract host for :authority header
        authority = headers.delete("host")
        if authority.nil? || authority.empty?
          # For now, require host header to be provided
          raise ArgumentError.new("Missing host header")
        end
        request_headers[":authority"] = authority

        # Add other headers
        headers.each { |k, v| request_headers[k.downcase] = v }

        # Encode headers
        encoded_headers = @hpack_encoder.encode(request_headers)

        # Send HEADERS frame
        flags = body.nil? ? HeadersFrame::FLAG_END_STREAM | HeadersFrame::FLAG_END_HEADERS : HeadersFrame::FLAG_END_HEADERS
        headers_frame = HeadersFrame.new(stream_id, encoded_headers, flags)
        write_frame(headers_frame)

        # Send DATA frame if body exists
        if body
          data_frame = DataFrame.new(stream_id, body.to_slice, DataFrame::FLAG_END_STREAM)
          write_frame(data_frame)
        end
      end

      private def read_response(stream_id : StreamId) : Response
        read_response_with_timeout(stream_id, Time.monotonic)
      end

      private def read_response_with_timeout(stream_id : StreamId, start_time : Time::Span) : Response
        response_headers = Headers.new
        response_body = IO::Memory.new
        status_code = 0

        loop do
          # Check timeout before each frame read
          if Time.monotonic - start_time > @request_timeout
            return Response.error(0, "Request timeout", "HTTP/2")
          end

          # Set socket timeout for the read operation
          io = @socket.to_io
          if io.responds_to?(:read_timeout=)
            remaining_time = @request_timeout - (Time.monotonic - start_time)
            if remaining_time > 0.seconds
              io.read_timeout = remaining_time
            else
              return Response.error(0, "Request timeout", "HTTP/2")
            end
          end

          frame = read_frame

          case frame
          when HeadersFrame
            # Decode headers
            decoded = @hpack_decoder.decode(frame.header_block)
            decoded.each do |name, value|
              if name == ":status"
                status_code = value.to_i
              else
                response_headers[name] = value
              end
            end

            if frame.end_stream?
              break
            end
          when DataFrame
            if frame.stream_id == stream_id
              response_body.write(frame.data)
              if frame.end_stream?
                break
              end
            end
          when RstStreamFrame
            if frame.stream_id == stream_id
              raise ConnectionError.new("Stream reset: #{frame.error_code}")
            end
          when GoawayFrame
            raise ConnectionError.new("Connection closed by server: #{frame.error_code}")
          when SettingsFrame
            handle_settings_frame(frame)
          when PingFrame
            # Respond to PING if not ACK
            unless frame.ack?
              pong = PingFrame.new(frame.opaque_data, ack: true)
              write_frame(pong)
            end
          when WindowUpdateFrame
            # Update flow control windows
            if frame.stream_id == 0
              @connection_window_size += frame.window_size_increment
            end
          else
            # Ignore other frames
          end
        end

        Response.new(
          status: status_code,
          headers: response_headers,
          body: response_body.to_s,
          protocol: "HTTP/2"
        )
      rescue IO::TimeoutError
        Response.error(0, "Request timeout", "HTTP/2")
      end

      private def handle_settings_frame(frame : SettingsFrame) : Nil
        return if frame.ack?

        frame.settings.each do |identifier, value|
          case identifier
          when SettingIdentifier::HeaderTableSize
            @remote_settings.header_table_size = value
            # TODO: Handle HPACK table size update
          when SettingIdentifier::MaxConcurrentStreams
            @remote_settings.max_concurrent_streams = value
          when SettingIdentifier::InitialWindowSize
            @remote_settings.initial_window_size = value
          when SettingIdentifier::MaxFrameSize
            @remote_settings.max_frame_size = value
          when SettingIdentifier::MaxHeaderListSize
            @remote_settings.max_header_list_size = value
          end
        end
      end

      private def write_frame(frame : Frame) : Nil
        io = @socket.to_io
        io.write(frame.to_bytes)
        io.flush
      end

      private def read_frame : Frame
        Frame.from_io(@socket.to_io, @remote_settings.max_frame_size)
      end

      def get(path : String, headers : Headers = Headers.new) : Response
        request("GET", path, headers)
      end

      def post(path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        request("POST", path, headers, body)
      end

      def put(path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        request("PUT", path, headers, body)
      end

      def delete(path : String, headers : Headers = Headers.new) : Response
        request("DELETE", path, headers)
      end

      def head(path : String, headers : Headers = Headers.new) : Response
        request("HEAD", path, headers)
      end

      def patch(path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        request("PATCH", path, headers, body)
      end

      # Compatibility methods for tests
      def send_frame(frame : Frame) : Nil
        @mutex.synchronize do
          write_frame(frame)
        end
      end

      def receive_frame : Frame?
        @mutex.synchronize do
          read_frame
        end
      rescue
        nil
      end

      def set_batch_processing(enabled : Bool) : Nil
        # No-op for simplified client
      end

      def ensure_connection_setup : Nil
        # Connection setup happens in initialize
      end
    end
  end
end