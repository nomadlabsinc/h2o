require "../tls"
require "../preface"

module H2O
  module H2
    class Client < BaseConnection
      property socket : TlsSocket
      property stream_pool : StreamPool
      property local_settings : Settings
      property remote_settings : Settings
      property hpack_encoder : HPACK::Encoder
      property hpack_decoder : HPACK::Decoder
      property connection_window_size : Int32
      property last_stream_id : StreamId
      property closed : Bool
      property closing : Bool
      property reader_fiber : FiberRef
      property writer_fiber : FiberRef
      property dispatcher_fiber : FiberRef
      property fibers_started : Bool
      property outgoing_frames : OutgoingFrameChannel
      property incoming_frames : IncomingFrameChannel

      def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds)
        verify_mode : OpenSSL::SSL::VerifyMode = determine_verify_mode(hostname)
        @socket = TlsSocket.new(hostname, port, verify_mode: verify_mode, connect_timeout: connect_timeout)
        validate_http2_negotiation

        @stream_pool = StreamPool.new
        @local_settings = Settings.new
        @remote_settings = Settings.new
        @hpack_encoder = HPACK::Encoder.new
        @hpack_decoder = HPACK::Decoder.new
        @connection_window_size = 65535
        @last_stream_id = 0_u32
        @closed = false
        @closing = false

        @outgoing_frames = OutgoingFrameChannel.new(100)
        @incoming_frames = IncomingFrameChannel.new(100)

        @reader_fiber = nil
        @writer_fiber = nil
        @dispatcher_fiber = nil
        @fibers_started = false

        setup_connection
      end

      def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response?
        raise ConnectionError.new("Connection is closed") if @closed

        ensure_fibers_started

        stream : Stream = @stream_pool.create_stream
        send_request_headers(stream, method, path, headers, body)
        send_request_body(stream, body) if body
        stream.await_response
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

      private def determine_verify_mode(hostname : String) : OpenSSL::SSL::VerifyMode
        local_host : Bool = hostname == "localhost" || hostname == "127.0.0.1"
        local_host ? OpenSSL::SSL::VerifyMode::NONE : OpenSSL::SSL::VerifyMode::PEER
      end

      private def send_request_headers(stream : Stream, method : String, path : String, headers : Headers, body : String?) : Nil
        request_headers : Headers = build_request_headers(method, path, headers)
        encoded_headers : Bytes = @hpack_encoder.encode(request_headers)
        flags : UInt8 = HeadersFrame::FLAG_END_HEADERS | (body.nil? ? HeadersFrame::FLAG_END_STREAM : 0_u8)
        headers_frame : HeadersFrame = HeadersFrame.new(stream.id, encoded_headers, flags)
        send_frame(headers_frame)
        stream.send_headers(headers_frame)
      end

      private def send_request_body(stream : Stream, body : String) : Nil
        data_frame : DataFrame = DataFrame.new(stream.id, body.to_slice, DataFrame::FLAG_END_STREAM)
        send_frame(data_frame)
        stream.send_data(data_frame)
      end

      private def validate_http2_negotiation : Nil
        unless @socket.negotiated_http2?
          raise ConnectionError.new("HTTP/2 not negotiated via ALPN")
        end
      end

      private def ensure_fibers_started : Nil
        return if @fibers_started

        @fibers_started = true
        start_fibers
      end

      private def fiber_still_running? : Bool
        return false unless @fibers_started

        # Check if any fiber is still alive and not finished
        reader_alive : Bool = @reader_fiber.try(&.dead?) == false
        writer_alive : Bool = @writer_fiber.try(&.dead?) == false
        dispatcher_alive : Bool = @dispatcher_fiber.try(&.dead?) == false

        reader_alive || writer_alive || dispatcher_alive
      end

      private def setup_connection : Nil
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
            if @socket.to_io.responds_to?(:read_timeout)
              @socket.to_io.read_timeout = 100.milliseconds
            end

            frame = Frame.from_io(@socket.to_io)

            # Check if we should still send the frame
            unless @closed
              @incoming_frames.send(frame)
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
        loop do
          break if @closed

          begin
            select
            when frame = @outgoing_frames.receive
              begin
                @socket.to_io.write(frame.to_bytes)
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
          decoded_headers = @hpack_decoder.decode(frame.header_block)
          stream.receive_headers(frame, decoded_headers)
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
        request_headers[":authority"] = headers.delete("host") || ""

        headers.each do |name, value|
          lowercase_name : String = name.downcase
          request_headers[lowercase_name] = value
        end
        request_headers
      end
    end
  end
end
