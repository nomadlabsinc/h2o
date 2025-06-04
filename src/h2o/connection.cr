require "./tls"
require "./preface"

module H2O
  class Connection
    property socket : TlsSocket
    property stream_pool : StreamPool
    property local_settings : Settings
    property remote_settings : Settings
    property hpack_encoder : HPACK::Encoder
    property hpack_decoder : HPACK::Decoder
    property connection_window_size : Int32
    property last_stream_id : StreamId
    property closed : Bool
    property reader_fiber : Fiber?
    property writer_fiber : Fiber?
    property dispatcher_fiber : Fiber?
    property outgoing_frames : Channel(Frame)
    property incoming_frames : Channel(Frame)

    def initialize(hostname : String, port : Int32)
      @socket = TlsSocket.new(hostname, port)
      validate_http2_negotiation

      @stream_pool = StreamPool.new
      @local_settings = Settings.new
      @remote_settings = Settings.new
      @hpack_encoder = HPACK::Encoder.new
      @hpack_decoder = HPACK::Decoder.new
      @connection_window_size = 65535
      @last_stream_id = 0_u32
      @closed = false

      @outgoing_frames = Channel(Frame).new(100)
      @incoming_frames = Channel(Frame).new(100)

      setup_connection
      start_fibers
    end

    def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response?
      raise ConnectionError.new("Connection is closed") if @closed

      stream = @stream_pool.create_stream
      request_headers = build_request_headers(method, path, headers)

      encoded_headers = @hpack_encoder.encode(request_headers)
      headers_frame = HeadersFrame.new(
        stream.id,
        encoded_headers,
        HeadersFrame::FLAG_END_HEADERS | (body.nil? ? HeadersFrame::FLAG_END_STREAM : 0_u8)
      )

      send_frame(headers_frame)
      stream.send_headers(headers_frame)

      if body
        data_frame = DataFrame.new(stream.id, body.to_slice, DataFrame::FLAG_END_STREAM)
        send_frame(data_frame)
        stream.send_data(data_frame)
      end

      stream.await_response
    end

    def ping(data : Bytes = Bytes.new(8)) : Bool
      ping_frame = PingFrame.new(data)
      send_frame(ping_frame)

      timeout = 5.seconds
      start_time = Time.monotonic

      loop do
        if Time.monotonic - start_time > timeout
          return false
        end

        sleep 0.1
        break if @closed
      end

      true
    end

    def close : Nil
      return if @closed

      @closed = true
      goaway_frame = GoawayFrame.new(@last_stream_id, ErrorCode::NoError)
      send_frame(goaway_frame)

      @outgoing_frames.close
      @incoming_frames.close
      @socket.close
    end

    private def validate_http2_negotiation : Nil
      unless @socket.negotiated_http2?
        raise ConnectionError.new("HTTP/2 not negotiated via ALPN")
      end
    end

    private def setup_connection : Nil
      Preface.send_preface(@socket)

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
          frame = Frame.from_io(@socket)
          @incoming_frames.send(frame)
        rescue ex : IO::Error
          Log.error { "Reader error: #{ex.message}" }
          break
        rescue ex : FrameError
          Log.error { "Frame error: #{ex.message}" }
          send_goaway(ErrorCode::ProtocolError)
          break
        end
      end
    end

    private def writer_loop : Nil
      loop do
        select
        when frame = @outgoing_frames.receive
          begin
            @socket.write(frame.to_bytes)
            @socket.flush
          rescue ex : IO::Error
            Log.error { "Writer error: #{ex.message}" }
            break
          end
        when timeout(1.second)
          break if @closed
        end
      end
    end

    private def dispatcher_loop : Nil
      loop do
        select
        when frame = @incoming_frames.receive
          handle_frame(frame)
        when timeout(1.second)
          break if @closed
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

        if response = stream.response
          decoded_headers.each { |name, value| response.headers[name] = value }
          if status = decoded_headers[":status"]?
            response.status = status.to_i32
          end
        end

        stream.receive_headers(frame)
      when DataFrame
        stream.receive_data(frame)

        if stream.needs_window_update?
          window_update = stream.create_window_update(32768)
          send_frame(window_update)
        end
      when RstStreamFrame
        stream.receive_rst_stream(frame)
        @stream_pool.remove_stream(frame.stream_id)
      end
    end

    private def send_frame(frame : Frame) : Nil
      @outgoing_frames.send(frame)
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

      headers.each { |name, value| request_headers[name.downcase] = value }
      request_headers
    end
  end
end
