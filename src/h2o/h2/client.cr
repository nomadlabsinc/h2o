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
require "../object_pool"
require "../io_optimizer"
require "../stream"

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

      # I/O optimizations
      property batched_writer : IOOptimizer::SynchronizedWriter?
      property zero_copy_reader : IOOptimizer::ZeroCopyReader?
      property io_optimization_enabled : Bool

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

        # Initialize I/O optimizations (temporarily disabled for stability)
        @io_optimization_enabled = false # Disabled until socket state conflicts are fully resolved
        @batched_writer = nil
        @zero_copy_reader = nil

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

          # I/O optimizations disabled for test mocks by default
          @io_optimization_enabled = false
          @batched_writer = nil
          @zero_copy_reader = nil
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
            response = read_response_with_timeout(stream_id, start_time)

            # Flush any pending batched data after request completes
            if @io_optimization_enabled && (writer = @batched_writer)
              writer.flush
              @socket.to_io.flush
            end

            response
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
            send_goaway_if_needed

            # Flush any pending batched data and ensure socket is flushed
            if @io_optimization_enabled && (writer = @batched_writer)
              writer.flush
              @socket.to_io.flush
            end
          rescue IO::Error
            # Best effort - ignore I/O errors during cleanup
          rescue
            # Best effort - ignore other errors during cleanup
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
      rescue ex : IO::Error
        Log.error { "I/O error during server preface validation: #{ex.message}" }
        false
      rescue ex : Socket::Error
        Log.error { "Socket error during server preface validation: #{ex.message}" }
        false
      rescue ex : OpenSSL::Error
        Log.error { "SSL error during server preface validation: #{ex.message}" }
        false
      rescue ex : H2O::ProtocolError
        Log.error { "HTTP/2 protocol error during server preface validation: #{ex.message}" }
        false
      rescue ex
        Log.error { "Unexpected error during server preface validation: #{ex.class}: #{ex.message}" }
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
        headers_frame = H2O.frame_pools.acquire_headers_frame(stream_id, encoded_headers, flags)
        begin
          write_frame(headers_frame)
        ensure
          H2O.frame_pools.release(headers_frame)
        end

        # Send DATA frame if body exists
        if body
          data_frame = H2O.frame_pools.acquire_data_frame(stream_id, body.to_slice, DataFrame::FLAG_END_STREAM)
          begin
            write_frame(data_frame)
          ensure
            H2O.frame_pools.release(data_frame)
          end
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

          # Don't set socket timeout - let the overall request timeout handle it

          frame = read_frame

          case frame
          when HeadersFrame
            if frame.stream_id == stream_id
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
            # Update HPACK encoder table size to match server setting
            @hpack_encoder.dynamic_table_size = value.to_i32
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
        frame_bytes = frame.to_bytes

        if @io_optimization_enabled && (writer = @batched_writer)
          # Optimize frame writing strategy based on size and type
          if should_flush_immediately?(frame, frame_bytes.size)
            flush_frame_immediately(writer, frame_bytes)
          else
            # Small non-control frames: batch for optimal throughput
            writer.add(frame_bytes)
          end
        else
          # Fallback to direct I/O
          write_frame_direct(frame_bytes)
        end
      end

      private def should_flush_immediately?(frame : Frame, size : Int32) : Bool
        size >= IOOptimizer::MEDIUM_BUFFER_SIZE ||
          frame.is_a?(SettingsFrame | PingFrame | GoawayFrame | RstStreamFrame)
      end

      private def flush_frame_immediately(writer : IOOptimizer::SynchronizedWriter, frame_bytes : Bytes) : Nil
        # Large frames or control frames: flush any pending data, then write directly for optimal latency
        writer.flush
        # Write large frames directly to socket to avoid double buffering
        write_frame_direct(frame_bytes)
      end

      private def write_frame_direct(frame_bytes : Bytes) : Nil
        io = @socket.to_io
        start_time = Time.monotonic
        io.write(frame_bytes)
        io.flush

        # Track statistics for direct writes when optimization is enabled
        if @io_optimization_enabled && (writer = @batched_writer)
          writer.track_direct_write(frame_bytes.size, Time.monotonic - start_time)
        end
      end

      private def read_frame : Frame
        if @io_optimization_enabled && (reader = @zero_copy_reader)
          # Use optimized frame reading with zero-copy reader through IO wrapper
          # This maintains code reuse while leveraging optimized I/O
          io_wrapper = ZeroCopyIOWrapper.new(reader)
          Frame.from_io(io_wrapper, @remote_settings.max_frame_size)
        else
          # Fallback to standard frame reading
          Frame.from_io(@socket.to_io, @remote_settings.max_frame_size)
        end
      end

      # IO wrapper that bridges ZeroCopyReader to standard IO interface
      # This eliminates code duplication while preserving optimizations
      private class ZeroCopyIOWrapper < IO
        def initialize(@reader : IOOptimizer::ZeroCopyReader)
        end

        def read(slice : Bytes) : Int32
          @reader.read_into(slice)
        end

        def write(slice : Bytes) : Nil
          raise IO::Error.new("Write not supported on ZeroCopyIOWrapper")
        end

        def read_fully(slice : Bytes) : Nil
          @reader.read_fully_into(slice)
        end

        def flush : Nil
          # No-op for read-only wrapper
        end

        def close : Nil
          # No-op - underlying reader is managed externally
        end
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
      rescue IO::Error | IO::TimeoutError
        # Expected errors during frame reading
        nil
      rescue
        # Unexpected errors during frame reading
        Log.debug { "Unexpected error in receive_frame" }
        nil
      end

      def set_batch_processing(enabled : Bool) : Nil
        # No-op for simplified client
      end

      def ensure_connection_setup : Nil
        # Connection setup happens in initialize
      end

      # Send GOAWAY frame if needed during connection termination
      private def send_goaway_if_needed : Nil
        # Only send GOAWAY if connection isn't already closed and we haven't already sent one
        # Don't send GOAWAY for normal request completion - only for connection termination
        if !@closing
          @closing = true
          # last_stream_id should be the highest stream ID we've successfully processed
          last_processed_stream_id = @current_stream_id > 1 ? @current_stream_id - 2 : 0_u32
          goaway_frame = GoawayFrame.new(last_processed_stream_id, ErrorCode::NoError)
          write_frame(goaway_frame)
        end
      end

      # Get I/O performance statistics
      def io_statistics : IOOptimizer::IOStats?
        @mutex.synchronize do
          return nil unless @io_optimization_enabled

          stats = IOOptimizer::IOStats.new

          if writer = @batched_writer
            stats.bytes_written = writer.stats.bytes_written
            stats.write_operations = writer.stats.write_operations
            stats.total_write_time = writer.stats.total_write_time
            stats.batches_flushed = writer.stats.batches_flushed
          end

          if reader = @zero_copy_reader
            stats.bytes_read = reader.stats.bytes_read
            stats.read_operations = reader.stats.read_operations
            stats.total_read_time = reader.stats.total_read_time
          end

          stats
        end
      end
    end
  end
end
