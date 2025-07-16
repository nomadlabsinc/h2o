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
require "../io_adapter"
require "../protocol_engine"
require "../network_transport"

module H2O
  module H2
    Log = ::Log.for("h2o.h2")

    # HTTP/2 client using ProtocolEngine architecture
    # Supports both network and custom transports through IoAdapter
    class Client < BaseConnection
      property socket : TlsSocket | TcpSocket
      property io_adapter : IoAdapter
      property protocol_engine : ProtocolEngine
      property request_timeout : Time::Span
      property connect_timeout : Time::Span

      # I/O optimizations
      property batched_writer : IOOptimizer::BatchedWriter?
      property zero_copy_reader : IOOptimizer::ZeroCopyReader?
      property io_optimization_enabled : Bool

      # Single mutex for all operations
      property mutex : Mutex

      # Response tracking for synchronous request/response
      property pending_responses : Hash(StreamId, Channel(Response))

      # Compatibility properties for interface consistency
      property closing : Bool

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

        @io_adapter = NetworkTransport.new(@socket)
        @protocol_engine = ProtocolEngine.new(@io_adapter)
        @request_timeout = request_timeout
        @connect_timeout = connect_timeout
        @mutex = Mutex.new
        @pending_responses = Hash(StreamId, Channel(Response)).new
        @closing = false

        # Initialize I/O optimizations (disable reader/writer optimizations due to socket state conflicts)
        @io_optimization_enabled = !H2O.env_flag_enabled?("H2O_DISABLE_IO_OPTIMIZATION")
        if @io_optimization_enabled
          IOOptimizer::SocketOptimizer.optimize(@socket.to_io)
          # Also set TCP_NODELAY directly on our socket if possible
          case socket = @socket
          when H2O::TlsSocket
            success = socket.set_tcp_nodelay(true)
            Log.debug { "H2::Client: TLS socket TCP_NODELAY: #{success ? "set" : "failed"}" }
          when H2O::TcpSocket
            # TCP socket should already be handled by IOOptimizer
            Log.debug { "H2::Client: TCP socket TCP_NODELAY handled by IOOptimizer" }
          end
          # TODO: Re-enable I/O optimizations after resolving socket state conflicts.
          # The BatchedWriter and ZeroCopyReader optimizations are currently disabled because they cause
          # socket state conflicts during HTTP/2 frame processing, leading to test timeouts and connection issues.
          # Future re-enablement strategy:
          # 1. Investigate socket state management in IOOptimizer classes
          # 2. Ensure proper coordination between batched writes and frame boundaries
          # 3. Add comprehensive tests for concurrent I/O operations
          # 4. Consider alternative buffering strategies that don't interfere with HTTP/2 protocol handling
          @batched_writer = nil   # Disabled - causes socket writing issues
          @zero_copy_reader = nil # Disabled - causes socket reading issues
        else
          @batched_writer = nil
          @zero_copy_reader = nil
        end

        # Set up response callback
        setup_protocol_callbacks

        # Establish connection through protocol engine
        unless @protocol_engine.establish_connection
          raise ConnectionError.new("Failed to establish HTTP/2 connection")
        end
      end

      # Alternative constructor accepting an IoAdapter directly
      # Useful for testing with InMemoryTransport or custom transport implementations
      def initialize(@io_adapter : IoAdapter, connect_timeout : Time::Span = 5.seconds, request_timeout : Time::Span = 5.seconds)
        # For IoAdapter constructor, we don't have a direct socket reference
        @socket = uninitialized TlsSocket | TcpSocket

        @protocol_engine = ProtocolEngine.new(@io_adapter)
        @request_timeout = request_timeout
        @connect_timeout = connect_timeout
        @mutex = Mutex.new
        @pending_responses = Hash(StreamId, Channel(Response)).new
        @closing = false

        # I/O optimizations disabled for custom adapters by default
        @io_optimization_enabled = false
        @batched_writer = nil
        @zero_copy_reader = nil

        # Set up response callback
        setup_protocol_callbacks

        # Establish connection through protocol engine
        unless @protocol_engine.establish_connection
          raise ConnectionError.new("Failed to establish HTTP/2 connection")
        end
      end

      # Test-only initializer for injecting a mock IO (legacy compatibility)
      {% if flag?(:test) %}
        def initialize(@socket : IO, connect_timeout : Time::Span = 5.seconds, request_timeout : Time::Span = 5.seconds)
          # Wrap the IO in a simple adapter for legacy test compatibility
          @io_adapter = TestIOAdapter.new(@socket)
          @protocol_engine = ProtocolEngine.new(@io_adapter)
          @request_timeout = request_timeout
          @connect_timeout = connect_timeout
          @mutex = Mutex.new
          @pending_responses = Hash(StreamId, Channel(Response)).new
          @closing = false

          # I/O optimizations disabled for test mocks by default
          @io_optimization_enabled = false
          @batched_writer = nil
          @zero_copy_reader = nil

          # Set up response callback
          setup_protocol_callbacks
        end
      {% end %}

      def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        return Response.error(0, "Connection is closed", "HTTP/2") if @protocol_engine.closed?

        # Use a timeout for the entire request
        start_time = Time.monotonic

        begin
          # Synchronize the request sending and response reading
          @mutex.synchronize do
            # Check timeout before starting
            if Time.monotonic - start_time > @request_timeout
              return Response.error(0, "Request timeout", "HTTP/2")
            end

            # Check if we can create a new stream based on MAX_CONCURRENT_STREAMS
            if max_streams = @protocol_engine.remote_settings.max_concurrent_streams
              # Since we only support one stream at a time currently, we just need to ensure
              # we're allowed to create at least one stream
              if max_streams == 0
                raise ConnectionError.new("Server does not allow any concurrent streams")
              end
            end

            # Send request through protocol engine
            stream_id = @protocol_engine.send_request(method, path, headers, body)

            # Set up response channel for this stream
            response_channel = Channel(Response).new
            @pending_responses[stream_id] = response_channel

            # Wait for response with timeout
            select
            when response = response_channel.receive
              @pending_responses.delete(stream_id)
              response
            when timeout(@request_timeout)
              @pending_responses.delete(stream_id)
              Response.error(0, "Request timeout", "HTTP/2")
            end
          end
        rescue ex : Exception
          Log.error { "Request failed: #{ex.message}" }
          Response.error(0, ex.message || "Unknown error", "HTTP/2")
        end
      end

      def close : Nil
        @mutex.synchronize do
          return if @protocol_engine.closed?

          @closing = true

          begin
            # Close through protocol engine (sends GOAWAY)
            @protocol_engine.close

            # Flush any pending batched data and ensure socket is flushed
            if @io_optimization_enabled && (writer = @batched_writer)
              writer.flush
              if !@socket.class.name.includes?("uninitialized")
                @socket.to_io.flush
              end
            end
          rescue IO::Error
            # Best effort - ignore I/O errors during cleanup
          rescue
            # Best effort - ignore other errors during cleanup
          end

          # Close any pending response channels
          @pending_responses.each_value(&.close)
          @pending_responses.clear
        end
      end

      def closed? : Bool
        @protocol_engine.closed?
      end

      # Send a PING frame to check connection health and optionally measure RTT
      def ping(timeout : Time::Span = 5.seconds) : Time::Span?
        @mutex.synchronize do
          raise ConnectionError.new("Connection is closed") if @protocol_engine.closed?

          # Delegate to protocol engine
          @protocol_engine.ping(timeout)
        end
      rescue IO::TimeoutError
        nil
      end

      private def setup_protocol_callbacks : Nil
        # Set up response callback for the protocol engine
        @protocol_engine.on_response = ->(stream_id : StreamId, response : Response) {
          if channel = @pending_responses[stream_id]?
            channel.send(response)
          end
          nil
        }

        # Set up error callback
        @protocol_engine.on_error = ->(ex : Exception) {
          Log.error { "Protocol error: #{ex.message}" }
          # Close any pending response channels with error
          @pending_responses.each_value do |channel|
            error_response = Response.error(0, ex.message || "Protocol error", "HTTP/2")
            channel.send(error_response) rescue nil
          end
          @pending_responses.clear
          nil
        }

        # Set up connection closed callback
        @protocol_engine.on_connection_closed = -> {
          # Close any pending response channels
          @pending_responses.each_value(&.close)
          @pending_responses.clear
          nil
        }
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
            Log.debug { "Response reading timed out" }
            return Response.error(0, "Request timeout", "HTTP/2")
          end

          # Don't set socket timeout - let the overall request timeout handle it

          frame = read_frame
          Log.debug { "Read frame: #{frame.class} stream_id=#{frame.stream_id}" }

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
          when SettingIdentifier::EnablePush
            @remote_settings.enable_push = value != 0
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

      private def flush_frame_immediately(writer : IOOptimizer::BatchedWriter, frame_bytes : Bytes) : Nil
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

      # Get access to the underlying ProtocolEngine for advanced usage
      def protocol_engine : ProtocolEngine
        @protocol_engine
      end

      # Get access to the underlying IoAdapter for advanced usage
      def io_adapter : IoAdapter
        @io_adapter
      end

      # Simple IoAdapter wrapper for legacy test compatibility
      {% if flag?(:test) %}
        private class TestIOAdapter < IoAdapter
          def initialize(@io : IO)
            @closed = false
            @data_callback = nil
            @close_callback = nil
          end

          def read_bytes(buffer_size : Int32) : Bytes?
            return nil if @closed

            begin
              bytes = Bytes.new(buffer_size)
              bytes_read = @io.read(bytes)
              return nil if bytes_read == 0

              result = bytes[0, bytes_read]
              @data_callback.try(&.call(result))
              result
            rescue
              @closed = true
              nil
            end
          end

          def write_bytes(bytes : Bytes) : Int32
            return 0 if @closed

            begin
              @io.write(bytes)
              @io.flush
              bytes.size
            rescue
              @closed = true
              0
            end
          end

          def close : Nil
            return if @closed
            @closed = true
            @io.close rescue nil
            @close_callback.try(&.call)
          end

          def closed? : Bool
            @closed
          end

          def on_data_available(&block : Bytes -> Nil) : Nil
            @data_callback = block
          end

          def on_closed(&block : -> Nil) : Nil
            @close_callback = block
          end
        end
      {% end %}
    end
  end
end
