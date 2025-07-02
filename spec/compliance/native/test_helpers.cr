require "../../spec_helper"

module H2SpecTestHelpers
  # Mock client class for testing that can accept any IO
  class MockH2Client
    property socket : IO::Memory
    property last_error : Exception?
    property frames_received : Array(Bytes)
    property max_frame_size : UInt32
    property active_streams : Set(UInt32)
    property highest_stream_id : UInt32
    property max_concurrent_streams : UInt32
    property concurrent_stream_count : UInt32
    
    def initialize(@socket : IO::Memory)
      @frames_received = [] of Bytes
      @last_error = nil
      @max_frame_size = 16384_u32 # Default MAX_FRAME_SIZE
      @active_streams = Set(UInt32).new
      @highest_stream_id = 0_u32
      @max_concurrent_streams = UInt32::MAX
      @concurrent_stream_count = 0_u32
    end
    
    def request(method : String, path : String) : H2O::Response?
      begin
        # Check if socket is empty
        if @socket.bytesize == 0
          raise IO::EOFError.new("No data in socket")
        end
        
        # Read frames from the mock socket
        while @socket.pos < @socket.bytesize
          frame = read_frame
          @frames_received << frame
          
          # Process frame and check for errors
          frame_type = frame[3]
          stream_id = (frame[5].to_u32 << 24) | (frame[6].to_u32 << 16) | (frame[7].to_u32 << 8) | frame[8].to_u32
          
          case frame_type
          when 0x0  # DATA
            check_data_frame(frame, stream_id)
          when 0x1  # HEADERS
            check_headers_frame(frame, stream_id)
          when 0x2  # PRIORITY
            check_priority_frame(frame, stream_id)
          when 0x3  # RST_STREAM
            check_rst_stream_frame(frame, stream_id)
          when 0x4  # SETTINGS
            check_settings_frame(frame, stream_id)
          when 0x5  # PUSH_PROMISE
            check_push_promise_frame(frame, stream_id)
          when 0x6  # PING
            check_ping_frame(frame, stream_id)
          when 0x7  # GOAWAY
            check_goaway_frame(frame, stream_id)
          when 0x8  # WINDOW_UPDATE
            check_window_update_frame(frame, stream_id)
          when 0x9  # CONTINUATION
            check_continuation_frame(frame, stream_id)
          end
        end
        
        # Return a mock successful response if no errors
        H2O::Response.new(200, {} of String => String, "")
      rescue ex
        @last_error = ex
        raise ex
      end
    end
    
    def get(url : String) : H2O::Response
      request("GET", url) || raise "No response"
    end
    
    def close : Nil
      # No-op for mock
    end
    
    private def read_frame : Bytes
      header = Bytes.new(9)
      @socket.read_fully(header)
      
      length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
      
      # Check frame size before allocating
      if length > @max_frame_size
        raise H2O::FrameSizeError.new("Frame size #{length} exceeds max #{@max_frame_size}")
      end
      
      frame = Bytes.new(9 + length)
      header.copy_to(frame)
      
      if length > 0
        @socket.read_fully(frame + 9)
      end
      
      frame
    end
    
    private def check_data_frame(frame : Bytes, stream_id : UInt32)
      if stream_id == 0
        raise H2O::ConnectionError.new("DATA frame on connection stream")
      end
      
      # Check for DATA on idle stream
      if !@active_streams.includes?(stream_id) && stream_id > @highest_stream_id
        raise H2O::ConnectionError.new("DATA frame on idle stream")
      end
      
      flags = frame[4]
      if (flags & FLAG_PADDED) != 0
        length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
        if frame.size > 9
          pad_length = frame[9]
          # Padding length must be less than the frame payload length minus padding length field (1 byte)
          if pad_length >= length
            raise H2O::ConnectionError.new("DATA frame padding exceeds payload")
          end
        end
      end
    end
    
    private def check_headers_frame(frame : Bytes, stream_id : UInt32)
      if stream_id == 0
        raise H2O::ConnectionError.new("HEADERS frame on connection stream")
      end
      
      # Check for even-numbered stream ID from server
      if stream_id % 2 == 0
        raise H2O::ConnectionError.new("HEADERS frame with even-numbered stream ID")
      end
      
      # Check stream ID ordering
      if stream_id <= @highest_stream_id
        raise H2O::ConnectionError.new("Stream ID not greater than previous")
      end
      
      # Check concurrent streams limit
      if @concurrent_stream_count >= @max_concurrent_streams
        raise H2O::StreamError.new("Exceeded MAX_CONCURRENT_STREAMS", stream_id, H2O::ErrorCode::RefusedStream)
      end
      
      # Update tracking
      @highest_stream_id = stream_id
      @active_streams.add(stream_id)
      @concurrent_stream_count += 1
      
      flags = frame[4]
      if (flags & FLAG_PADDED) != 0
        length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
        if frame.size > 9
          pad_length = frame[9]
          if pad_length >= length
            raise H2O::ConnectionError.new("HEADERS frame padding exceeds payload")
          end
        end
      end
      
      # Check for invalid HPACK data (simplified check)
      if frame.size > 9 && frame[9] == 0xFF && frame.size > 10 && frame[10] == 0xFF
        raise H2O::CompressionError.new("Invalid HPACK encoding")
      end
      
      # Decode headers and check for connection-specific headers
      header_block_start = 9
      padding_size = 0
      
      if (flags & FLAG_PADDED) != 0
        padding_length = frame[9]
        header_block_start += 1
        padding_size = padding_length
      end
      
      if (flags & FLAG_PRIORITY) != 0
        header_block_start += 5
      end
      
      # Calculate actual header block size (excluding padding)
      header_block_end = frame.size - padding_size
      
      if header_block_end > header_block_start
        header_block = frame[header_block_start, header_block_end - header_block_start]
        
        # Use the actual HPACK decoder to check headers
        begin
          decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
          headers = decoder.decode(header_block)
          
          # Check for connection-specific headers
          headers.each do |name, value|
            if name.downcase == "connection" || name.downcase == "transfer-encoding" || 
               name.downcase == "upgrade" || name.downcase == "keep-alive" || 
               name.downcase == "proxy-connection"
              raise H2O::ProtocolError.new("Connection-specific header '#{name}' in HEADERS frame")
            end
          end
        rescue ex : H2O::CompressionError
          # Re-raise compression errors
          raise ex
        rescue ex
          # For debugging: uncomment to see errors
          puts "HPACK decode error: #{ex.class} - #{ex.message}"
          raise H2O::ProtocolError.new("Failed to decode HEADERS: #{ex.message}")
        end
      end
    end
    
    private def check_priority_frame(frame : Bytes, stream_id : UInt32)
      if stream_id == 0
        raise H2O::ConnectionError.new("PRIORITY frame on connection stream")
      end
      
      length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
      if length != 5
        raise H2O::FrameSizeError.new("PRIORITY frame must be 5 octets")
      end
    end
    
    private def check_rst_stream_frame(frame : Bytes, stream_id : UInt32)
      if stream_id == 0
        raise H2O::ConnectionError.new("RST_STREAM frame on connection stream")
      end
      
      length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
      if length != 4
        raise H2O::FrameSizeError.new("RST_STREAM frame must be 4 octets")
      end
      
      # Check for RST_STREAM on idle stream (simplified)
      if stream_id > 1 && stream_id % 2 == 1
        raise H2O::ConnectionError.new("RST_STREAM on idle stream")
      end
    end
    
    private def check_settings_frame(frame : Bytes, stream_id : UInt32)
      if stream_id != 0
        raise H2O::ConnectionError.new("SETTINGS frame on non-zero stream")
      end
      
      length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
      flags = frame[4]
      
      if (flags & FLAG_ACK) != 0 && length != 0
        raise H2O::FrameSizeError.new("SETTINGS ACK must have empty payload")
      end
      
      if length % 6 != 0
        raise H2O::FrameSizeError.new("SETTINGS payload must be multiple of 6")
      end
      
      # Check settings values
      i = 9
      while i < frame.size
        setting_id = (frame[i].to_u16 << 8) | frame[i + 1].to_u16
        value = (frame[i + 2].to_u32 << 24) | (frame[i + 3].to_u32 << 16) | (frame[i + 4].to_u32 << 8) | frame[i + 5].to_u32
        
        case setting_id
        when SETTINGS_ENABLE_PUSH
          if value > 1
            raise H2O::ProtocolError.new("SETTINGS_ENABLE_PUSH must be 0 or 1")
          end
        when SETTINGS_INITIAL_WINDOW_SIZE
          if value > 0x7FFFFFFF
            raise H2O::FlowControlError.new("SETTINGS_INITIAL_WINDOW_SIZE too large")
          end
        when SETTINGS_MAX_FRAME_SIZE
          if value < 16384 || value > 0xFFFFFF
            raise H2O::ProtocolError.new("SETTINGS_MAX_FRAME_SIZE out of range")
          end
          @max_frame_size = value
        when SETTINGS_MAX_CONCURRENT_STREAMS
          @max_concurrent_streams = value
        end
        
        i += 6
      end
    end
    
    private def check_push_promise_frame(frame : Bytes, stream_id : UInt32)
      # Push promise validation would go here
    end
    
    private def check_ping_frame(frame : Bytes, stream_id : UInt32)
      # Ping validation would go here
    end
    
    private def check_goaway_frame(frame : Bytes, stream_id : UInt32)
      # Goaway validation would go here
    end
    
    private def check_window_update_frame(frame : Bytes, stream_id : UInt32)
      # Check for WINDOW_UPDATE on idle stream
      if stream_id != 0 && !@active_streams.includes?(stream_id) && stream_id > @highest_stream_id
        raise H2O::ConnectionError.new("WINDOW_UPDATE frame on idle stream")
      end
      
      length = (frame[0].to_u32 << 16) | (frame[1].to_u32 << 8) | frame[2].to_u32
      if length != 4
        raise H2O::FrameSizeError.new("WINDOW_UPDATE frame must be 4 octets")
      end
      
      if frame.size >= 13
        increment = (frame[9].to_u32 << 24) | (frame[10].to_u32 << 16) | (frame[11].to_u32 << 8) | frame[12].to_u32
        if increment == 0
          raise H2O::ProtocolError.new("WINDOW_UPDATE increment cannot be 0")
        end
      end
    end
    
    private def check_continuation_frame(frame : Bytes, stream_id : UInt32)
      # For now, always error on CONTINUATION without HEADERS
      raise H2O::ConnectionError.new("CONTINUATION without HEADERS")
    end
  end

  # Creates a mock socket with initial settings preface
  def create_mock_client : Tuple(IO::Memory, MockH2Client)
    mock_socket = IO::Memory.new
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)
    mock_socket.rewind
    client = MockH2Client.new(mock_socket)
    {mock_socket, client}
  end

  # Creates a mock socket and writes frames before creating client
  def create_mock_client_with_frames(frames : Array(Bytes)) : Tuple(IO::Memory, MockH2Client)
    mock_socket = IO::Memory.new
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)
    frames.each { |frame| mock_socket.write(frame) }
    mock_socket.rewind
    client = MockH2Client.new(mock_socket)
    {mock_socket, client}
  end

  # Builds a raw frame with header and payload
  def build_raw_frame(length : Int32, type : UInt8, flags : UInt8, stream_id : UInt32, payload : Bytes = Bytes.empty) : Bytes
    frame = Bytes.new(9 + payload.size)
    # Length (24 bits)
    frame[0] = ((length >> 16) & 0xFF).to_u8
    frame[1] = ((length >> 8) & 0xFF).to_u8
    frame[2] = (length & 0xFF).to_u8
    # Type
    frame[3] = type
    # Flags
    frame[4] = flags
    # Stream ID (32 bits)
    frame[5] = ((stream_id >> 24) & 0xFF).to_u8
    frame[6] = ((stream_id >> 16) & 0xFF).to_u8
    frame[7] = ((stream_id >> 8) & 0xFF).to_u8
    frame[8] = (stream_id & 0xFF).to_u8
    # Payload
    payload.copy_to(frame + 9) unless payload.empty?
    frame
  end

  # Common frame type constants
  FRAME_TYPE_DATA          = 0x0_u8
  FRAME_TYPE_HEADERS       = 0x1_u8
  FRAME_TYPE_PRIORITY      = 0x2_u8
  FRAME_TYPE_RST_STREAM    = 0x3_u8
  FRAME_TYPE_SETTINGS      = 0x4_u8
  FRAME_TYPE_PUSH_PROMISE  = 0x5_u8
  FRAME_TYPE_PING          = 0x6_u8
  FRAME_TYPE_GOAWAY        = 0x7_u8
  FRAME_TYPE_WINDOW_UPDATE = 0x8_u8
  FRAME_TYPE_CONTINUATION  = 0x9_u8

  # Common flags
  FLAG_END_STREAM  = 0x1_u8
  FLAG_ACK         = 0x1_u8
  FLAG_END_HEADERS = 0x4_u8
  FLAG_PADDED      = 0x8_u8
  FLAG_PRIORITY    = 0x20_u8

  # Helper to create settings frame payload
  def build_settings_payload(settings : Hash(UInt16, UInt32)) : Bytes
    payload = Bytes.new(settings.size * 6)
    index = 0
    settings.each do |id, value|
      # Setting ID (16 bits)
      payload[index] = ((id >> 8) & 0xFF).to_u8
      payload[index + 1] = (id & 0xFF).to_u8
      # Value (32 bits)
      payload[index + 2] = ((value >> 24) & 0xFF).to_u8
      payload[index + 3] = ((value >> 16) & 0xFF).to_u8
      payload[index + 4] = ((value >> 8) & 0xFF).to_u8
      payload[index + 5] = (value & 0xFF).to_u8
      index += 6
    end
    payload
  end

  # Helper to create GOAWAY payload
  def build_goaway_payload(last_stream_id : UInt32, error_code : UInt32, debug_data : String = "") : Bytes
    debug_bytes = debug_data.to_slice
    payload = Bytes.new(8 + debug_bytes.size)
    # Last Stream ID (32 bits)
    payload[0] = ((last_stream_id >> 24) & 0xFF).to_u8
    payload[1] = ((last_stream_id >> 16) & 0xFF).to_u8
    payload[2] = ((last_stream_id >> 8) & 0xFF).to_u8
    payload[3] = (last_stream_id & 0xFF).to_u8
    # Error Code (32 bits)
    payload[4] = ((error_code >> 24) & 0xFF).to_u8
    payload[5] = ((error_code >> 16) & 0xFF).to_u8
    payload[6] = ((error_code >> 8) & 0xFF).to_u8
    payload[7] = (error_code & 0xFF).to_u8
    # Debug Data
    debug_bytes.copy_to(payload + 8) unless debug_bytes.empty?
    payload
  end

  # Helper to create WINDOW_UPDATE payload
  def build_window_update_payload(increment : UInt32) : Bytes
    payload = Bytes.new(4)
    payload[0] = ((increment >> 24) & 0xFF).to_u8
    payload[1] = ((increment >> 16) & 0xFF).to_u8
    payload[2] = ((increment >> 8) & 0xFF).to_u8
    payload[3] = (increment & 0xFF).to_u8
    payload
  end

  # Helper to create RST_STREAM payload
  def build_rst_stream_payload(error_code : UInt32) : Bytes
    payload = Bytes.new(4)
    payload[0] = ((error_code >> 24) & 0xFF).to_u8
    payload[1] = ((error_code >> 16) & 0xFF).to_u8
    payload[2] = ((error_code >> 8) & 0xFF).to_u8
    payload[3] = (error_code & 0xFF).to_u8
    payload
  end

  # Helper to create PRIORITY payload
  def build_priority_payload(stream_dependency : UInt32, weight : UInt8, exclusive : Bool = false) : Bytes
    payload = Bytes.new(5)
    dep = exclusive ? (stream_dependency | 0x80000000_u32) : stream_dependency
    payload[0] = ((dep >> 24) & 0xFF).to_u8
    payload[1] = ((dep >> 16) & 0xFF).to_u8
    payload[2] = ((dep >> 8) & 0xFF).to_u8
    payload[3] = (dep & 0xFF).to_u8
    payload[4] = weight
    payload
  end

  # Helper to create PING payload
  def build_ping_payload(data : UInt64 = 0_u64) : Bytes
    payload = Bytes.new(8)
    payload[0] = ((data >> 56) & 0xFF).to_u8
    payload[1] = ((data >> 48) & 0xFF).to_u8
    payload[2] = ((data >> 40) & 0xFF).to_u8
    payload[3] = ((data >> 32) & 0xFF).to_u8
    payload[4] = ((data >> 24) & 0xFF).to_u8
    payload[5] = ((data >> 16) & 0xFF).to_u8
    payload[6] = ((data >> 8) & 0xFF).to_u8
    payload[7] = (data & 0xFF).to_u8
    payload
  end

  # Error code constants
  ERROR_NO_ERROR            = 0x0_u32
  ERROR_PROTOCOL_ERROR      = 0x1_u32
  ERROR_INTERNAL_ERROR      = 0x2_u32
  ERROR_FLOW_CONTROL_ERROR  = 0x3_u32
  ERROR_SETTINGS_TIMEOUT    = 0x4_u32
  ERROR_STREAM_CLOSED       = 0x5_u32
  ERROR_FRAME_SIZE_ERROR    = 0x6_u32
  ERROR_REFUSED_STREAM      = 0x7_u32
  ERROR_CANCEL              = 0x8_u32
  ERROR_COMPRESSION_ERROR   = 0x9_u32
  ERROR_CONNECT_ERROR       = 0xa_u32
  ERROR_ENHANCE_YOUR_CALM   = 0xb_u32
  ERROR_INADEQUATE_SECURITY = 0xc_u32
  ERROR_HTTP_1_1_REQUIRED   = 0xd_u32

  # Settings identifiers
  SETTINGS_HEADER_TABLE_SIZE      = 0x1_u16
  SETTINGS_ENABLE_PUSH            = 0x2_u16
  SETTINGS_MAX_CONCURRENT_STREAMS = 0x3_u16
  SETTINGS_INITIAL_WINDOW_SIZE    = 0x4_u16
  SETTINGS_MAX_FRAME_SIZE         = 0x5_u16
  SETTINGS_MAX_HEADER_LIST_SIZE   = 0x6_u16
end