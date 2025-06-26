require "../tls"
require "../tcp_socket"
require "../preface"
require "../frames/frame_batch_processor"

module H2O
  module H2
    class Client < BaseConnection
      property socket : TlsSocket | TcpSocket
      property stream_pool : StreamPool
      property local_settings : Settings
      property remote_settings : Settings
      property hpack_encoder : HPACK::Encoder
      property hpack_decoder : HPACK::Decoder
      property connection_window_size : Int32
      property last_stream_id : UInt32
      property closed : Bool
      property closing : Bool
      property reader_fiber : FiberRef
      property writer_fiber : FiberRef
      property dispatcher_fiber : FiberRef
      property fibers_started : Bool
      property connection_setup : Bool
      property outgoing_frames : OutgoingFrameChannel
      property incoming_frames : IncomingFrameChannel
      property continuation_limits : ContinuationLimits
      property header_fragments : Hash(UInt32, HeaderFragmentState)
      property batch_processor : FrameBatchProcessor
      property enable_batch_processing : Bool
      property request_timeout : Time::Span

      def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds, request_timeout : Time::Span = 5.seconds, verify_ssl : Bool = true, use_tls : Bool = true)
        if use_tls
          verify_mode : OpenSSL::SSL::VerifyMode = verify_ssl ? OpenSSL::SSL::VerifyMode::PEER : OpenSSL::SSL::VerifyMode::NONE
          Log.debug { "Creating H2::Client for #{hostname}:#{port} with TLS and verify_mode=#{verify_mode}" }
          @socket = TlsSocket.new(hostname, port, verify_mode: verify_mode, connect_timeout: connect_timeout)
          validate_http2_negotiation
        else
          Log.debug { "Creating H2::Client for #{hostname}:#{port} with prior knowledge (no TLS)" }
          @socket = TcpSocket.new(hostname, port)
        end

        @stream_pool = StreamPool.new
        @local_settings = Settings.new
        @remote_settings = Settings.new
        @hpack_encoder = HPACK::Encoder.new
        @hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
        @connection_window_size = 65535
        @last_stream_id = 0_u32
        @closed = false
        @closing = false

        @outgoing_frames = OutgoingFrameChannel.new(1000)
        @incoming_frames = IncomingFrameChannel.new(1000)

        @continuation_limits = ContinuationLimits.new
        @header_fragments = Hash(UInt32, HeaderFragmentState).new

        @batch_processor = FrameBatchProcessor.new
        @enable_batch_processing = false # Disable batch processing for debugging
        @request_timeout = request_timeout

        @reader_fiber = nil
        @writer_fiber = nil
        @dispatcher_fiber = nil
        @fibers_started = false
        @connection_setup = false

        # Defer connection setup until first request for performance
      end

      def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        return Response.error(0, "Connection is closed", "HTTP/2") if @closed

        ensure_fibers_started

        stream : Stream? = nil
        begin
          stream = @stream_pool.create_stream
          send_request_headers(stream, method, path, headers, body)
          send_request_body(stream, body) if body

          # Wait for response with proper error handling
          if response = stream.await_response(@request_timeout)
            response
          else
            Response.error(408, "Request timeout", "HTTP/2")
          end
        rescue ex : TimeoutError | ConnectionError
          Log.error { "H2 request failed: #{ex.message}" }

          # Clean up the stream if request failed
          @stream_pool.remove_stream(stream.id) if stream

          # Return error response instead of nil
          Response.error(0, ex.message.to_s, "HTTP/2")
        rescue ex : Exception
          Log.error { "H2 request unexpected error: #{ex.message}" }

          # Clean up the stream if request failed
          @stream_pool.remove_stream(stream.id) if stream

          Response.error(0, ex.message.to_s, "HTTP/2")
        end
      end

      def ping(data : Bytes = Bytes.new(8)) : Bool
        ensure_fibers_started

        ping_frame : PingFrame = PingFrame.new(data)
        send_frame(ping_frame)

        timeout_handler : TimeoutCallback = -> { false }
        result : TimeoutResult = Timeout(TimeoutResult).execute_with_handler(5.seconds, timeout_handler) do
          until @closed
            sleep 0.1
          end
          true
        end

        result || false
      end

      def closed? : Bool
        @closed
      end

      def set_batch_processing(enabled : Bool) : Nil
        @enable_batch_processing = enabled
      end

      def close : Nil
        return if @closed || @closing

        # Mark as closing to prevent concurrent close attempts
        @closing = true

        # Set closed flag to stop new operations
        @closed = true

        # Close channels immediately to force fibers to exit
        close_channels_immediately

        # Wait for fibers to actually terminate
        wait_for_fiber_termination

        # Finally close the socket
        close_socket_safely
      end

      private def close_channels_immediately : Nil
        [@outgoing_frames, @incoming_frames].each do |channel|
          begin
            channel.close unless channel.closed?
          rescue
            # Ignore errors during channel close
          end
        end
      end

      private def wait_for_fiber_termination : Nil
        # Give fibers time to see closed channels and exit
        result = Timeout(Bool).execute_with_handler(1.second, -> { false }) do
          while fiber_still_running?
            sleep 5.milliseconds
          end
          true
        end

        unless result
          Log.warn { "Forcing fiber termination after timeout" }
        end

        # Additional safety delay
        sleep 100.milliseconds
      end

      private def close_socket_safely : Nil
        return if @socket.closed?

        begin
          @socket.close
        rescue ex : Exception
          Log.debug { "Error during socket close: #{ex.message}" }
        end

        # Additional safety delay to allow OpenSSL cleanup
        sleep 10.milliseconds
      rescue ex : Exception
        Log.debug { "Unexpected error in close_socket_safely: #{ex.message}" }
      end

      private def send_request_headers(stream : Stream, method : String, path : String, headers : Headers, body : String?) : Nil
        request_headers : Headers = build_request_headers(method, path, headers)
        encoded_headers : Bytes = @hpack_encoder.encode(request_headers)
        max_frame_size = @remote_settings.max_frame_size.to_i32

        if encoded_headers.size <= max_frame_size
          # Single HEADERS frame - fits within max frame size
          flags : UInt8 = HeadersFrame::FLAG_END_HEADERS | (body.nil? ? HeadersFrame::FLAG_END_STREAM : 0_u8)
          headers_frame : HeadersFrame = HeadersFrame.new(stream.id, encoded_headers, flags)
          send_frame(headers_frame)
          stream.send_headers(headers_frame)
        else
          # Multiple frames - fragment headers using CONTINUATION frames
          send_fragmented_headers(stream, encoded_headers, body.nil?, max_frame_size)
        end
      end

      private def send_fragmented_headers(stream : Stream, encoded_headers : Bytes, end_stream : Bool, max_frame_size : Int32) : Nil
        total_size = encoded_headers.size
        offset = 0

        while offset < total_size
          # Calculate chunk size for this frame
          remaining = total_size - offset
          chunk_size = Math.min(remaining, max_frame_size)

          # Extract chunk data
          chunk_data = encoded_headers[offset, chunk_size]

          # Determine if this is the last header frame
          is_last_header_frame = (offset + chunk_size) >= total_size

          if offset == 0
            # First frame is HEADERS frame
            flags : UInt8 = 0_u8
            flags |= HeadersFrame::FLAG_END_HEADERS if is_last_header_frame
            flags |= HeadersFrame::FLAG_END_STREAM if end_stream

            headers_frame : HeadersFrame = HeadersFrame.new(stream.id, chunk_data, flags)
            send_frame(headers_frame)
            stream.send_headers(headers_frame)
          else
            # Subsequent frames are CONTINUATION frames
            continuation_frame : ContinuationFrame = ContinuationFrame.new(stream.id, chunk_data, is_last_header_frame)
            send_frame(continuation_frame)
          end

          offset += chunk_size

          Log.debug { "Sent header frame chunk: #{chunk_size} bytes, total progress: #{offset}/#{total_size}" }
        end
      end

      private def send_request_body(stream : Stream, body : String) : Nil
        body_bytes = body.to_slice
        max_frame_size = @remote_settings.max_frame_size.to_i32

        if body_bytes.size <= max_frame_size
          # Single frame - body fits within max frame size
          data_frame : DataFrame = DataFrame.new(stream.id, body_bytes, DataFrame::FLAG_END_STREAM)
          send_frame(data_frame)
          stream.send_data(data_frame)
        else
          # Multiple frames - fragment body to honor max_frame_size
          send_fragmented_body(stream, body_bytes, max_frame_size)
        end
      end

      private def send_fragmented_body(stream : Stream, body_bytes : Bytes, max_frame_size : Int32) : Nil
        total_size = body_bytes.size
        offset = 0

        while offset < total_size
          # Calculate chunk size for this frame
          remaining = total_size - offset
          chunk_size = Math.min(remaining, max_frame_size)

          # Extract chunk data
          chunk_data = body_bytes[offset, chunk_size]

          # Determine if this is the last frame
          is_last_frame = (offset + chunk_size) >= total_size
          flags = is_last_frame ? DataFrame::FLAG_END_STREAM : 0_u8

          # Create and send data frame
          data_frame : DataFrame = DataFrame.new(stream.id, chunk_data, flags)
          send_frame(data_frame)
          stream.send_data(data_frame)

          offset += chunk_size

          Log.debug { "Sent DATA frame chunk: #{chunk_size} bytes, total progress: #{offset}/#{total_size}" }
        end
      end

      private def validate_http2_negotiation : Nil
        # Only validate ALPN negotiation for TLS sockets
        if socket = @socket.as?(TlsSocket)
          unless socket.negotiated_http2?
            raise ConnectionError.new("HTTP/2 not negotiated via ALPN")
          end
        end
        # For TCP sockets (prior knowledge), no validation needed
      end

      private def ensure_fibers_started : Nil
        return if @fibers_started

        start_fibers
        @fibers_started = true

        # Also perform connection setup if not done yet
        unless @connection_setup
          setup_connection_internal
          @connection_setup = true
        end
      end

      private def fiber_still_running? : Bool
        return false unless @fibers_started

        # Check if any fiber is still alive and not finished
        reader_alive : Bool = @reader_fiber.try(&.dead?) == false
        writer_alive : Bool = @writer_fiber.try(&.dead?) == false
        dispatcher_alive : Bool = @dispatcher_fiber.try(&.dead?) == false

        reader_alive || writer_alive || dispatcher_alive
      end

      private def setup_connection_internal : Nil
        # Send preface and initial settings - fibers are already started
        Preface.send_preface(@socket.to_io)

        initial_settings = Preface.create_initial_settings
        send_frame(initial_settings)
      end

      private def start_fibers : Nil
        @reader_fiber = spawn { reader_loop }
        @writer_fiber = spawn { writer_loop }
        @dispatcher_fiber = spawn { dispatcher_loop }
      end

      private def reader_loop : Nil
        loop do
          break if @closed

          begin
            # Use non-blocking approach with timeout
            io = @socket.to_io
            if io.responds_to?(:read_timeout=)
              io.read_timeout = 100.milliseconds
            end

            if @enable_batch_processing
              # Batch processing mode
              frames = @batch_processor.read_batch(io)

              # Send all frames unless closed
              unless @closed
                frames.each do |frame|
                  @incoming_frames.send(frame) unless @closed
                end
              end
            else
              # Single frame processing mode (fallback)
              frame = Frame.from_io(io)

              # Check if we should still send the frame
              unless @closed
                @incoming_frames.send(frame)
              end
            end
          rescue IO::TimeoutError
            # Timeout is expected, just continue loop to check @closed
            next
          rescue ex : IO::Error
            Log.error { "Reader error: #{ex.message}" }
            break
          rescue ex : FrameError
            Log.error { "Frame error: #{ex.message}" }
            send_goaway(ErrorCode::ProtocolError)
            break
          rescue Channel::ClosedError
            Log.debug { "Reader channel closed, exiting loop" }
            break
          end
        end
      end

      private def writer_loop : Nil
        write_buffer = IO::Memory.new(65536) # 64KB write buffer

        loop do
          break if @closed

          begin
            frames_to_write = Array(Frame).new

            # Try to collect multiple frames for batched writing
            select
            when frame = @outgoing_frames.receive
              frames_to_write << frame

              # Try to receive more frames without blocking
              while frames_to_write.size < 10
                select
                when next_frame = @outgoing_frames.receive
                  frames_to_write << next_frame
                else
                  break
                end
              end

              begin
                if frames_to_write.size == 1
                  # Single frame - write directly
                  @socket.to_io.write(frames_to_write.first.to_bytes)
                else
                  # Multiple frames - batch write
                  write_buffer.clear
                  frames_to_write.each do |queued_frame|
                    write_buffer.write(queued_frame.to_bytes)
                  end

                  @socket.to_io.write(write_buffer.to_slice)
                end
                @socket.to_io.flush
              rescue ex : IO::Error
                Log.error { "Writer error: #{ex.message}" }
                break
              end
            when timeout(1.second)
              break if @closed
            end
          rescue Channel::ClosedError
            Log.debug { "Writer channel closed, exiting loop" }
            break
          end
        end
      end

      private def dispatcher_loop : Nil
        loop do
          break if @closed

          begin
            select
            when frame = @incoming_frames.receive
              handle_frame(frame)
            when timeout(1.second)
              break if @closed
            end
          rescue Channel::ClosedError
            Log.debug { "Dispatcher channel closed, exiting loop" }
            break
          end
        end
      end

      private def handle_frame(frame : Frame) : Nil
        case frame
        when SettingsFrame
          handle_settings_frame(frame)
        when PingFrame
          handle_ping_frame(frame)
        when GoawayFrame
          handle_goaway_frame(frame)
        when WindowUpdateFrame
          handle_window_update_frame(frame)
        when HeadersFrame, DataFrame, RstStreamFrame
          handle_stream_frame(frame)
        when ContinuationFrame
          handle_continuation_frame(frame)
        else
          Log.warn { "Unhandled frame type: #{frame.frame_type}" }
        end
      end

      private def handle_settings_frame(frame : SettingsFrame) : Nil
        if frame.ack?
          return
        end

        frame.settings.each do |identifier, value|
          case identifier
          when .header_table_size?
            @remote_settings.header_table_size = value
            @hpack_encoder.dynamic_table.resize(value.to_i32)
          when .enable_push?
            @remote_settings.enable_push = value != 0
          when .max_concurrent_streams?
            @remote_settings.max_concurrent_streams = value
            @stream_pool.max_concurrent_streams = value
          when .initial_window_size?
            @remote_settings.initial_window_size = value
          when .max_frame_size?
            @remote_settings.max_frame_size = value
          when .max_header_list_size?
            @remote_settings.max_header_list_size = value
          end
        end

        ack_frame = Preface.create_settings_ack
        send_frame(ack_frame)
      end

      private def handle_ping_frame(frame : PingFrame) : Nil
        if frame.ack?
          return
        end

        ack_frame = frame.create_ack
        send_frame(ack_frame)
      end

      private def handle_goaway_frame(frame : GoawayFrame) : Nil
        @closed = true
        Log.info { "Received GOAWAY: #{frame.error_code}" }
      end

      private def handle_window_update_frame(frame : WindowUpdateFrame) : Nil
        if frame.stream_id == 0
          @connection_window_size += frame.window_size_increment.to_i32
        else
          stream = @stream_pool.get_stream(frame.stream_id)
          stream.receive_window_update(frame) if stream
        end
      end

      private def handle_stream_frame(frame : Frame) : Nil
        stream = @stream_pool.get_stream(frame.stream_id)
        return unless stream

        case frame
        when HeadersFrame
          if frame.end_headers?
            # Complete headers in single frame
            decoded_headers = @hpack_decoder.decode(frame.header_block)
            stream.receive_headers(frame, decoded_headers)
          else
            # Fragmented headers - start accumulation for CONTINUATION frames
            start_header_fragment(frame.stream_id, frame.header_block)
          end
        when DataFrame
          stream.receive_data(frame)

          if stream.needs_window_update?
            window_update = stream.create_window_update(32768)
            send_frame(window_update)
          end
        when RstStreamFrame
          stream.receive_rst_stream(frame)
          @stream_pool.track_stream_reset(frame.stream_id)
          @stream_pool.remove_stream(frame.stream_id)
        end
      end

      private def send_frame(frame : Frame) : Nil
        if @closed
          Log.warn { "Attempted to send frame on closed connection" }
          return
        end

        begin
          @outgoing_frames.send(frame)
        rescue Channel::ClosedError
          Log.warn { "Cannot send frame: connection closed" }
        end
      end

      private def send_goaway(error_code : ErrorCode) : Nil
        goaway_frame = GoawayFrame.new(@last_stream_id, error_code)
        send_frame(goaway_frame)
        @closed = true
      end

      private def build_request_headers(method : String, path : String, headers : Headers) : Headers
        request_headers = Headers.new
        request_headers[":method"] = method
        request_headers[":path"] = path
        request_headers[":scheme"] = "https"

        # Extract host for :authority header
        authority = headers.delete("host")
        if authority.nil? || authority.empty?
          raise ConnectionError.new("Missing host header for :authority")
        end
        request_headers[":authority"] = authority

        headers.each do |name, value|
          # Pre-size hash if not already done to avoid resizing during iteration
          request_headers[name.downcase] = value
        end
        request_headers
      end

      private def handle_continuation_frame(frame : ContinuationFrame) : Nil
        stream_id = frame.stream_id

        # Check if we have an ongoing header fragment for this stream
        unless @header_fragments.has_key?(stream_id)
          send_goaway(ErrorCode::ProtocolError)
          raise ContinuationFloodError.new("CONTINUATION frame without preceding HEADERS frame")
        end

        fragment_state = @header_fragments[stream_id]

        # Validate CONTINUATION frame limits
        new_continuation_count = fragment_state[:continuation_count] + 1
        if new_continuation_count > @continuation_limits.max_continuation_frames
          @header_fragments.delete(stream_id)
          send_goaway(ErrorCode::EnhanceYourCalm)
          raise ContinuationFloodError.new("Too many CONTINUATION frames: #{new_continuation_count}")
        end

        # Check accumulated size limits
        new_size = fragment_state[:accumulated_size] + frame.header_block.size
        if new_size > @continuation_limits.max_accumulated_size
          @header_fragments.delete(stream_id)
          send_goaway(ErrorCode::CompressionError)
          raise ContinuationFloodError.new("CONTINUATION frames exceed size limit: #{new_size} bytes")
        end

        # Accumulate the header block
        fragment_state[:buffer].write(frame.header_block)

        # Create updated fragment state (NamedTuple is immutable)
        updated_fragment_state = {
          stream_id:          stream_id,
          accumulated_size:   new_size,
          continuation_count: new_continuation_count,
          buffer:             fragment_state[:buffer],
        }
        @header_fragments[stream_id] = updated_fragment_state

        # If this is the final CONTINUATION frame, process the complete headers
        if frame.end_headers?
          process_accumulated_headers(stream_id)
        end
      end

      private def process_accumulated_headers(stream_id : UInt32) : Nil
        return unless fragment_state = @header_fragments.delete(stream_id)

        # Validate final header size
        total_size = fragment_state[:accumulated_size]
        if total_size > @continuation_limits.max_header_size
          send_goaway(ErrorCode::CompressionError)
          raise ContinuationFloodError.new("Final header size exceeds limit: #{total_size} bytes")
        end

        # Decode the complete header block
        accumulated_data = fragment_state[:buffer].to_slice
        begin
          decoded_headers = @hpack_decoder.decode(accumulated_data)

          # Find the stream and deliver the headers
          stream = @stream_pool.get_stream(stream_id)
          if stream
            # Create a synthetic HEADERS frame to maintain compatibility
            synthetic_headers = HeadersFrame.new(
              stream_id,
              accumulated_data,
              HeadersFrame::FLAG_END_HEADERS
            )
            stream.receive_headers(synthetic_headers, decoded_headers)
          end
        rescue ex : Exception
          send_goaway(ErrorCode::CompressionError)
          raise ContinuationFloodError.new("Header decompression failed: #{ex.message}")
        end
      end

      private def start_header_fragment(stream_id : UInt32, initial_data : Bytes) : Nil
        # Clean up any existing fragment for this stream (should not happen in well-formed HTTP/2)
        @header_fragments.delete(stream_id)

        # Validate initial size
        if initial_data.size > @continuation_limits.max_header_size
          send_goaway(ErrorCode::CompressionError)
          raise ContinuationFloodError.new("Initial header block too large: #{initial_data.size} bytes")
        end

        # Create new fragment state
        buffer = IO::Memory.new
        buffer.write(initial_data)

        @header_fragments[stream_id] = {
          stream_id:          stream_id,
          accumulated_size:   initial_data.size,
          continuation_count: 0,
          buffer:             buffer,
        }
      end
    end
  end
end
