require "../../spec_helper"
require "./mock_h2_validator"

module H2SpecSimpleHelpers
  # Validates that processing the given frames raises the expected error
  def expect_protocol_error(frames : Array(Bytes), error_type : Exception.class, message : String? = nil)
    validator = H2O::MockH2Validator.new
    
    expect_raises(error_type, message) do
      validator.validate_frames(frames)
    end
  end
  
  # Validates that processing the given frames succeeds
  def expect_valid_frames(frames : Array(Bytes))
    validator = H2O::MockH2Validator.new
    validator.validate_frames(frames).should be_true
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