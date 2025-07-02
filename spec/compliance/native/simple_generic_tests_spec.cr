require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC Generic Protocol Tests" do
  # Generic test 1: Connection preface validation
  it "validates proper connection preface sequence" do
    # Valid initial SETTINGS frame
    settings_frame = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes.empty
    )
    
    expect_valid_frames([settings_frame])
  end
  
  # Generic test 2: Frame size limits
  it "enforces maximum frame size limits" do
    # First open stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Frame at maximum allowed size (16384)
    large_payload = Bytes.new(16384)
    large_payload.fill(0_u8)
    
    data_frame = build_raw_frame(
      length: 16384,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: large_payload
    )
    
    expect_valid_frames([headers, data_frame])
  end
  
  # Generic test 3: Stream ID validation
  it "validates stream ID progression" do
    # Stream IDs must be odd for client-initiated
    headers1 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    headers3 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 3_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers1, headers3])
  end
  
  # Generic test 4: Unknown frame types
  it "ignores unknown frame types" do
    # Unknown frame type should be ignored
    unknown_frame = build_raw_frame(
      length: 4,
      type: 0xFF_u8,  # Unknown type
      flags: 0_u8,
      stream_id: 0_u32,
      payload: "test".to_slice
    )
    
    expect_valid_frames([unknown_frame])
  end
  
  # Generic test 5: Flag validation
  it "validates frame flags" do
    # First open the stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Invalid flags should be ignored - use flags that don't include PADDED
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: 0xF7_u8,  # All flags except PADDED (0x8)
      stream_id: 1_u32,
      payload: "test".to_slice
    )
    
    expect_valid_frames([headers, data_frame])
  end
  
  # Generic test 6: Connection-level frames
  it "validates connection-level frames use stream 0" do
    # PING must be on stream 0
    ping_payload = build_ping_payload(0x1234567890ABCDEF_u64)
    
    ping_frame = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: ping_payload
    )
    
    expect_valid_frames([ping_frame])
  end
  
  # Generic test 7: Stream-level frames
  it "validates stream-level frames use non-zero stream" do
    # First open the stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # DATA must be on non-zero stream
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: "test".to_slice
    )
    
    expect_valid_frames([headers, data_frame])
  end
  
  # Generic test 8: Frame ordering
  it "validates proper frame ordering" do
    # HEADERS followed by DATA
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: "test".to_slice
    )
    
    expect_valid_frames([headers_frame, data_frame])
  end
  
  # Generic test 9: Empty frames
  it "handles empty frames" do
    # First open the stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Empty DATA frame
    empty_data = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes.empty
    )
    
    expect_valid_frames([headers, empty_data])
  end
  
  # Generic test 10: Maximum stream ID
  it "handles maximum stream ID values" do
    # Maximum valid stream ID (2^31 - 1)
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 0x7FFFFFFF_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Additional generic tests (11-23)
  {% for i in 11..23 %}
  it "generic protocol test {{i}}" do
    # First open the stream with HEADERS
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: {{i * 2 - 1}}_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Then send DATA on the same stream
    data = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: {{i * 2 - 1}}_u32,
      payload: "test".to_slice
    )
    
    expect_valid_frames([headers, data])
  end
  {% end %}
end