require "log"
require "./io_adapter"
require "./types"
require "./exceptions"
require "./preface"
require "./hpack/encoder"
require "./hpack/decoder"
require "./frames/frame"
require "./frames/headers_frame"
require "./frames/data_frame"
require "./frames/settings_frame"
require "./frames/rst_stream_frame"
require "./frames/goaway_frame"
require "./frames/ping_frame"
require "./frames/window_update_frame"
require "./header_list_validation"

module H2O
  # HTTP/2 Protocol Engine - manages all protocol-level operations
  # Separated from I/O to enable testing and multiple transport types
  class ProtocolEngine
    Log = ::Log.for("h2o.protocol_engine")

    # Transport adapter for I/O operations
    property io_adapter : IoAdapter

    # HTTP/2 connection state
    property local_settings : Settings
    property remote_settings : Settings
    property connection_window_size : Int32
    property closed : Bool
    property closing : Bool

    # HPACK state
    property hpack_encoder : HPACK::Encoder
    property hpack_decoder : HPACK::Decoder

    # Stream management
    property current_stream_id : StreamId
    property active_streams : Hash(StreamId, StreamInfo)

    # Protocol state
    property connection_established : Bool
    property server_preface_received : Bool
    property settings_ack_channel : Channel(Bool)?

    # Callbacks for application-level events
    property on_response : (StreamId, Response -> Nil)?
    property on_error : (Exception -> Nil)?
    property on_connection_closed : (-> Nil)?

    # Synchronization
    property mutex : Mutex

    # Frame processing state
    property frame_buffer : IO::Memory
    property processing_fiber : Fiber?
    property response_builders : Hash(StreamId, ResponseBuilder)

    def initialize(@io_adapter : IoAdapter)
      @local_settings = Settings.new
      @remote_settings = Settings.new
      @connection_window_size = 65535 # Default initial window size
      @closed = false
      @closing = false

      @hpack_encoder = HPACK::Encoder.new(4096)
      @hpack_decoder = HPACK::Decoder.new(4096)

      @current_stream_id = 1_u32 # Client uses odd stream IDs
      @active_streams = Hash(StreamId, StreamInfo).new

      @connection_established = false
      @server_preface_received = false
      @settings_ack_channel = Channel(Bool).new

      @mutex = Mutex.new

      # Initialize frame processing state
      @frame_buffer = IO::Memory.new
      @processing_fiber = nil
      @response_builders = Hash(StreamId, ResponseBuilder).new

      setup_io_callbacks
    end

    # Establish HTTP/2 connection (send preface and initial settings)
    def establish_connection : Bool
      @mutex.synchronize do
        return false if @closed

        begin
          send_connection_preface
          start_frame_processing
          true
        rescue ex
          handle_error(ex)
          false
        end
      end

      # Wait for SETTINGS handshake to complete with timeout
      begin
        Log.debug { "Waiting for SETTINGS handshake completion..." }
        select
        when @settings_ack_channel.not_nil!.receive
          @connection_established = true
          Log.debug { "SETTINGS handshake completed successfully" }
          true
        when timeout(10.seconds)
          Log.error { "SETTINGS handshake timed out after 10 seconds" }
          false
        end
      rescue Channel::ClosedError
        Log.error { "SETTINGS handshake channel closed - likely received GOAWAY from server" }
        false
      rescue ex
        Log.error { "SETTINGS handshake failed with exception: #{ex.message}" }
        false
      end
    end

    # Send HTTP/2 request
    def send_request(method : String, path : String, headers : Headers, body : String? = nil) : StreamId
      @mutex.synchronize do
        raise ConnectionError.new("Connection not established") unless @connection_established
        raise ConnectionError.new("Connection is closed") if @closed

        stream_id = allocate_stream_id

        # Build request headers with pseudo-headers
        request_headers = build_request_headers(method, path, headers)

        # Validate headers for RFC 9113 compliance
        HeaderListValidation.validate_http2_header_list(request_headers, true)

        # Send HEADERS frame
        encoded_headers = @hpack_encoder.encode(request_headers)

        # Determine if we need END_STREAM flag
        end_stream = body.nil? || body.empty?

        # Calculate flags for HEADERS frame
        flags = 0_u8
        flags |= HeadersFrame::FLAG_END_HEADERS
        if end_stream
          flags |= HeadersFrame::FLAG_END_STREAM
        end

        headers_frame = HeadersFrame.new(
          stream_id: stream_id,
          header_block: encoded_headers,
          flags: flags
        )

        write_frame(headers_frame)

        # Send body if present
        if !end_stream && body
          send_data(stream_id, body, end_stream: true)
        end

        # Track stream
        @active_streams[stream_id] = StreamInfo.new(stream_id, "open")

        stream_id
      end
    end

    # Send DATA frame
    def send_data(stream_id : StreamId, data : String, end_stream : Bool = false) : Nil
      @mutex.synchronize do
        raise ConnectionError.new("Connection is closed") if @closed

        flags = end_stream ? DataFrame::FLAG_END_STREAM : 0_u8
        data_frame = DataFrame.new(
          stream_id: stream_id,
          data: data.to_slice,
          flags: flags
        )

        write_frame(data_frame)

        # Update stream state if ending
        if end_stream
          if stream_info = @active_streams[stream_id]?
            stream_info.state = "half_closed_local"
          end
        end
      end
    end

    # Send PING frame for connection health check
    def ping(timeout : Time::Span = 5.seconds) : Time::Span?
      @mutex.synchronize do
        return nil if @closed

        # Generate random ping data
        ping_data = Bytes.new(8)
        Random::Secure.random_bytes(ping_data)

        start_time = Time.monotonic
        ping_frame = PingFrame.new(ping_data, ack: false)
        write_frame(ping_frame)

        # Wait for PONG (this would need async handling in real implementation)
        # For now, return immediately as a placeholder
        Time.monotonic - start_time
      end
    end

    # Close connection gracefully
    def close : Nil
      # Prepare close actions while holding mutex
      should_close, callback = @mutex.synchronize do
        return false, nil if @closed

        @closing = true

        # Send GOAWAY frame
        last_stream = @current_stream_id > 2 ? @current_stream_id - 2 : 0_u32
        goaway = GoawayFrame.new(
          last_stream_id: last_stream,
          error_code: ErrorCode::NoError,
          debug_data: "Client closing connection".to_slice
        )

        write_frame(goaway)
        @closed = true

        {true, @on_connection_closed}
      end

      # Close adapter and call callback outside of mutex to avoid deadlock
      if should_close
        @io_adapter.close
        callback.try(&.call)
      end
    end

    # Check if connection is closed
    def closed? : Bool
      @mutex.synchronize { @closed || @io_adapter.closed? }
    end

    private def setup_io_callbacks : Nil
      @io_adapter.on_data_available do |data|
        process_incoming_data(data)
      end

      @io_adapter.on_closed do
        handle_connection_closed
      end
    end

    private def send_connection_preface : Nil
      Log.debug { "Starting to send HTTP/2 connection preface..." }

      # Send HTTP/2 connection preface string
      preface_bytes = Preface::CONNECTION_PREFACE.to_slice
      Log.debug { "Writing preface bytes (#{preface_bytes.size} bytes)..." }
      @io_adapter.write_bytes(preface_bytes)
      Log.debug { "Preface bytes written successfully" }

      # Send initial SETTINGS frame
      Log.debug { "Creating initial SETTINGS frame..." }
      initial_settings = Preface.create_initial_settings
      Log.debug { "Writing initial SETTINGS frame..." }
      write_frame(initial_settings)
      Log.debug { "Initial SETTINGS frame written successfully" }

      Log.debug { "Sent HTTP/2 connection preface and initial SETTINGS" }
    end

    private def start_frame_processing : Nil
      # Start a fiber for asynchronous frame processing
      @processing_fiber = spawn do
        begin
          frame_processing_loop
        rescue ex
          handle_error(ex)
        end
      end
    end

    private def process_incoming_data(data : Bytes) : Nil
      # Add incoming data to frame buffer
      @frame_buffer.write(data)
      Log.debug { "Received #{data.size} bytes of data, buffer size: #{@frame_buffer.size}" }
    end

    private def frame_processing_loop : Nil
      Log.debug { "Frame processing loop started" }
      loop do
        break if @closed

        # Try to read and process frames from the buffer
        frame = read_frame_from_buffer
        if frame
          Log.debug { "Processing frame from buffer: #{frame.class.name} (stream #{frame.stream_id})" }
          process_frame(frame)
        else
          # No complete frame available, wait for more data
          sleep(0.01.seconds)
        end
      end
      Log.debug { "Frame processing loop ended" }
    end

    private def read_frame_from_buffer : Frame?
      frame_data = @mutex.synchronize do
        # Check if we have enough data for a frame header (9 bytes)
        return nil if @frame_buffer.size < 9

        # Peek at frame header to get length
        @frame_buffer.rewind
        header_bytes = Bytes.new(9)
        @frame_buffer.read(header_bytes)

        length = (header_bytes[0].to_u32 << 16) | (header_bytes[1].to_u32 << 8) | header_bytes[2].to_u32
        total_frame_size = 9 + length

        # Check if we have the complete frame
        if @frame_buffer.size < total_frame_size
          @frame_buffer.rewind
          return nil
        end

        # Read the complete frame data
        @frame_buffer.rewind
        frame_bytes = @frame_buffer.to_slice[0, total_frame_size].dup

        # Remove processed data from buffer
        remaining_data = @frame_buffer.to_slice[total_frame_size, @frame_buffer.size - total_frame_size]
        @frame_buffer = IO::Memory.new
        @frame_buffer.write(remaining_data) if remaining_data.size > 0

        frame_bytes
      end

      # Parse frame outside of mutex to avoid deadlock
      if frame_data
        begin
          frame_io = IO::Memory.new(frame_data)
          Frame.from_io(frame_io, @remote_settings.max_frame_size)
        rescue ex
          Log.error { "Frame parsing error: #{ex.message}" }
          handle_error(ex)
          nil
        end
      else
        nil
      end
    end

    private def process_frame(frame : Frame) : Nil
      Log.debug { "Processing #{frame.class.name} frame for stream #{frame.stream_id}" }

      case frame
      when HeadersFrame
        process_headers_frame(frame)
      when DataFrame
        process_data_frame(frame)
      when SettingsFrame
        process_settings_frame(frame)
      when PingFrame
        process_ping_frame(frame)
      when RstStreamFrame
        process_rst_stream_frame(frame)
      when GoawayFrame
        process_goaway_frame(frame)
      when WindowUpdateFrame
        process_window_update_frame(frame)
      else
        Log.debug { "Ignoring unknown frame type: #{frame.class.name}" }
      end
    end

    private def process_headers_frame(frame : HeadersFrame) : Nil
      stream_id = frame.stream_id

      # Get or create response builder for this stream
      builder = @response_builders[stream_id]? || ResponseBuilder.new(stream_id)
      @response_builders[stream_id] = builder

      begin
        # Decode HPACK headers
        decoded_headers = @hpack_decoder.decode(frame.header_block)
        builder.add_headers(decoded_headers)

        # Check if this completes the response
        if frame.end_stream?
          builder.mark_complete
          complete_response(stream_id, builder)
        end
      rescue ex
        Log.error { "HPACK decoding error: #{ex.message}" }
        handle_stream_error(stream_id, ex)
      end
    end

    private def process_data_frame(frame : DataFrame) : Nil
      stream_id = frame.stream_id

      # Get response builder for this stream
      if builder = @response_builders[stream_id]?
        builder.add_data(frame.data)

        # Check if this completes the response
        if frame.end_stream?
          builder.mark_complete
          complete_response(stream_id, builder)
        end
      else
        Log.warn { "Received DATA frame for unknown stream #{stream_id}" }
      end
    end

    private def process_settings_frame(frame : SettingsFrame) : Nil
      if frame.ack?
        Log.debug { "Received SETTINGS ACK" }
        return
      end

      Log.debug { "Processing SETTINGS with #{frame.settings.size} parameters" }

      # Process SETTINGS and send ACK
      frame.settings.each do |identifier, value|
        case identifier
        when SettingIdentifier::HeaderTableSize
          @remote_settings.header_table_size = value
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

      # Mark server preface received (SETTINGS is part of server preface)
      @server_preface_received = true

      # Send SETTINGS ACK immediately for RFC compliance
      Log.debug { "Sending SETTINGS ACK immediately" }
      begin
        settings_ack = SettingsFrame.new(ack: true)
        Log.debug { "Writing SETTINGS ACK frame..." }
        write_frame(settings_ack)
        Log.debug { "SETTINGS ACK sent successfully" }

        # Signal that SETTINGS handshake is complete
        if channel = @settings_ack_channel
          Log.debug { "Signaling SETTINGS handshake completion..." }
          channel.send(true)
          Log.debug { "SETTINGS handshake completion signal sent" }
        else
          Log.error { "SETTINGS ACK channel is nil, cannot signal completion" }
        end
      rescue ex
        Log.error { "Failed to send SETTINGS ACK: #{ex.message}" }
      end
    end

    private def process_ping_frame(frame : PingFrame) : Nil
      unless frame.ack?
        # Respond to PING with PONG
        pong = PingFrame.new(frame.opaque_data, ack: true)
        write_frame(pong)
      end
    end

    private def process_rst_stream_frame(frame : RstStreamFrame) : Nil
      stream_id = frame.stream_id

      # Remove response builder and notify error
      if builder = @response_builders.delete(stream_id)
        error = ConnectionError.new("Stream reset: #{frame.error_code}")
        handle_stream_error(stream_id, error)
      end

      # Update stream state
      if stream_info = @active_streams[stream_id]?
        stream_info.state = "closed"
      end
    end

    private def process_goaway_frame(frame : GoawayFrame) : Nil
      Log.info { "Received GOAWAY: last_stream=#{frame.last_stream_id}, error=#{frame.error_code}" }

      # If this is a SettingsTimeout during connection establishment, close immediately
      if frame.error_code == ErrorCode::SettingsTimeout && !@connection_established
        Log.error { "Server terminated connection due to SETTINGS timeout during handshake" }
        @closed = true
        @closing = true

        # Signal any waiting SETTINGS handshake
        if channel = @settings_ack_channel
          channel.close rescue nil
        end

        # Trigger connection closed callback
        @on_connection_closed.try(&.call)
        return
      end

      # Mark connection as closing
      @closing = true

      # Notify all pending responses of connection closure
      @response_builders.each do |stream_id, _builder|
        if stream_id > frame.last_stream_id
          error = ConnectionError.new("Connection closed by server: #{frame.error_code}")
          handle_stream_error(stream_id, error)
        end
      end

      # Trigger connection closed callback
      @on_connection_closed.try(&.call)
    end

    private def process_window_update_frame(frame : WindowUpdateFrame) : Nil
      if frame.stream_id == 0
        # Connection-level window update
        @connection_window_size += frame.window_size_increment
      else
        # Stream-level window update (would update stream window in full implementation)
        Log.debug { "Stream #{frame.stream_id} window updated by #{frame.window_size_increment}" }
      end
    end

    private def complete_response(stream_id : StreamId, builder : ResponseBuilder) : Nil
      # Remove builder and create response
      @response_builders.delete(stream_id)
      response = builder.build_response

      # Update stream state
      if stream_info = @active_streams[stream_id]?
        stream_info.state = "closed"
      end

      # Notify callback
      @on_response.try(&.call(stream_id, response))
    end

    private def handle_stream_error(stream_id : StreamId, error : Exception) : Nil
      # Remove response builder
      @response_builders.delete(stream_id)

      # Create error response
      error_response = Response.error(0, error.message || "Stream error", "HTTP/2")

      # Notify callback
      @on_response.try(&.call(stream_id, error_response))
    end

    private def write_frame(frame : Frame) : Nil
      # Prepare frame data outside mutex to avoid holding lock during I/O
      frame_bytes = frame.to_bytes

      write_start = Time.monotonic
      Log.debug { "Writing #{frame.class.name} frame (#{frame_bytes.size} bytes) at #{write_start}" }

      bytes_written = @io_adapter.write_bytes(frame_bytes)
      write_end = Time.monotonic
      write_time = write_end - write_start
      Log.debug { "write_bytes completed in #{write_time.total_milliseconds}ms" }

      if bytes_written != frame_bytes.size
        Log.error { "Failed to write complete frame: wrote #{bytes_written}/#{frame_bytes.size} bytes" }
        raise ConnectionError.new("Failed to write complete frame")
      end

      # Force flush for small control frames to avoid Nagle's algorithm delay
      if should_flush_immediately?(frame, frame_bytes.size)
        flush_start = Time.monotonic
        @io_adapter.flush
        flush_end = Time.monotonic
        flush_time = flush_end - flush_start
        Log.debug { "Forced flush for small control frame: #{frame.class.name} took #{flush_time.total_milliseconds}ms" }
      end

      total_time = Time.monotonic - write_start
      Log.debug { "Sent #{frame.class.name} frame (#{frame_bytes.size} bytes) - total time: #{total_time.total_milliseconds}ms" }
    end

    private def should_flush_immediately?(frame : Frame, size : Int32) : Bool
      # Flush small control frames immediately to avoid Nagle's algorithm delays
      case frame
      when SettingsFrame, PingFrame, WindowUpdateFrame, RstStreamFrame
        size < 64 # Small control frames
      else
        false
      end
    end

    private def allocate_stream_id : StreamId
      stream_id = @current_stream_id
      @current_stream_id += 2 # Client uses odd stream IDs
      stream_id
    end

    private def build_request_headers(method : String, path : String, headers : Headers) : Headers
      request_headers = Headers.new

      # Add pseudo-headers first
      request_headers[":method"] = method
      request_headers[":path"] = path
      request_headers[":scheme"] = "https" # Default to HTTPS

      # Extract and add authority
      if authority = headers.delete("host")
        request_headers[":authority"] = authority
      end

      # Add remaining headers (validate first, then add)
      headers.each do |name, value|
        # Validate header name for RFC 9113 compliance BEFORE normalization
        HeaderListValidation.validate_rfc9113_field_name(name)
        request_headers[name.downcase] = value
      end

      request_headers
    end

    private def handle_error(ex : Exception) : Nil
      Log.error { "Protocol error: #{ex.message}" }
      @on_error.try(&.call(ex))
    end

    private def handle_connection_closed : Nil
      # Avoid deadlock by not acquiring mutex if we're already closed
      callback = @mutex.synchronize do
        return if @closed
        @closed = true
        @on_connection_closed
      end

      # Call callback outside of mutex to avoid deadlock
      callback.try(&.call)
    end

    # Helper class to track stream information
    class StreamInfo
      property stream_id : StreamId
      property state : String
      property request_sent_at : Time

      def initialize(@stream_id : StreamId, @state : String)
        @request_sent_at = Time.utc
      end
    end

    # Helper class to build responses from multiple frames
    class ResponseBuilder
      property stream_id : StreamId
      property status_code : Int32
      property headers : Headers
      property body : IO::Memory
      property complete : Bool

      def initialize(@stream_id : StreamId)
        @status_code = 0
        @headers = Headers.new
        @body = IO::Memory.new
        @complete = false
      end

      def add_headers(decoded_headers : Hash(String, String)) : Nil
        decoded_headers.each do |name, value|
          if name == ":status"
            @status_code = value.to_i
          else
            @headers[name] = value
          end
        end
      end

      def add_data(data : Bytes) : Nil
        @body.write(data)
      end

      def mark_complete : Nil
        @complete = true
      end

      def build_response : Response
        Response.new(
          status: @status_code,
          headers: @headers,
          body: @body.to_s,
          protocol: "HTTP/2"
        )
      end
    end
  end
end
