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
    
    # Callbacks for application-level events
    property on_response : (StreamId, Response -> Nil)?
    property on_error : (Exception -> Nil)?
    property on_connection_closed : (-> Nil)?
    
    # Synchronization
    property mutex : Mutex
    
    def initialize(@io_adapter : IoAdapter)
      @local_settings = Settings.new
      @remote_settings = Settings.new
      @connection_window_size = 65535  # Default initial window size
      @closed = false
      @closing = false
      
      @hpack_encoder = HPACK::Encoder.new(4096)
      @hpack_decoder = HPACK::Decoder.new(4096)
      
      @current_stream_id = 1_u32  # Client uses odd stream IDs
      @active_streams = Hash(StreamId, StreamInfo).new
      
      @connection_established = false
      @server_preface_received = false
      
      @mutex = Mutex.new
      
      setup_io_callbacks
    end
    
    # Establish HTTP/2 connection (send preface and initial settings)
    def establish_connection : Bool
      @mutex.synchronize do
        return false if @closed
        
        begin
          send_connection_preface
          @connection_established = true
          start_frame_processing
          true
        rescue ex
          handle_error(ex)
          false
        end
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
      # Send HTTP/2 connection preface string
      preface_bytes = Preface::CONNECTION_PREFACE.to_slice
      @io_adapter.write_bytes(preface_bytes)
      
      # Send initial SETTINGS frame
      initial_settings = Preface.create_initial_settings
      write_frame(initial_settings)
      
      Log.debug { "Sent HTTP/2 connection preface and initial SETTINGS" }
    end
    
    private def start_frame_processing : Nil
      # In a real implementation, this would start a fiber for processing incoming frames
      # For now, we'll process frames synchronously
    end
    
    private def process_incoming_data(data : Bytes) : Nil
      # This would parse incoming data into frames and process them
      # Implementation would handle partial frames, buffering, etc.
      Log.debug { "Received #{data.size} bytes of data" }
    end
    
    private def write_frame(frame : Frame) : Nil
      frame_bytes = frame.to_bytes
      bytes_written = @io_adapter.write_bytes(frame_bytes)
      
      if bytes_written != frame_bytes.size
        raise ConnectionError.new("Failed to write complete frame")
      end
      
      Log.debug { "Sent #{frame.class.name} frame (#{frame_bytes.size} bytes)" }
    end
    
    private def allocate_stream_id : StreamId
      stream_id = @current_stream_id
      @current_stream_id += 2  # Client uses odd stream IDs
      stream_id
    end
    
    private def build_request_headers(method : String, path : String, headers : Headers) : Headers
      request_headers = Headers.new
      
      # Add pseudo-headers first
      request_headers[":method"] = method
      request_headers[":path"] = path
      request_headers[":scheme"] = "https"  # Default to HTTPS
      
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
  end
end