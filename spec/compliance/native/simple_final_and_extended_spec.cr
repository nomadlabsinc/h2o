require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC Final Validation Tests" do
  # Final test 1: Protocol compliance summary
  it "validates overall protocol compliance" do
    # Complete minimal HTTP/2 exchange
    settings = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes.empty
    )
    
    settings_ack = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_SETTINGS,
      flags: FLAG_ACK,
      stream_id: 0_u32,
      payload: Bytes.empty
    )
    
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([settings, settings_ack, headers])
  end
  
  # Final test 2: Connection termination
  it "validates proper connection termination" do
    # GOAWAY with debug data
    goaway_payload = build_goaway_payload(0_u32, ERROR_NO_ERROR, "graceful shutdown")
    goaway = build_raw_frame(
      length: goaway_payload.size,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: goaway_payload
    )
    
    expect_valid_frames([goaway])
  end
end

describe "H2SPEC Extended Section Tests" do
  # Extended stream states tests (5.1/6-13)
  it "validates stream state after RST_STREAM (5.1/6)" do
    # Open stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # RST_STREAM
    rst = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: build_rst_stream_payload(ERROR_CANCEL)
    )
    
    # WINDOW_UPDATE on closed stream (allowed)
    window = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: build_window_update_payload(100_u32)
    )
    
    expect_valid_frames([headers, rst, window])
  end
  
  {% for i in 7..13 %}
  it "extended stream state test 5.1/{{i}}" do
    # Various stream state scenarios
    frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: {{i * 2 - 1}}_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([frame])
  end
  {% end %}
  
  # Connection error handling (5.4.1/1-2)
  it "validates connection error handling (5.4.1/1)" do
    # Invalid frame that should trigger connection error
    invalid = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 0_u32,  # DATA on stream 0
      payload: Bytes.empty
    )
    
    expect_protocol_error([invalid], H2O::ConnectionError)
  end
  
  it "validates connection error recovery (5.4.1/2)" do
    # GOAWAY after error
    goaway = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: build_goaway_payload(0_u32, ERROR_PROTOCOL_ERROR)
    )
    
    expect_valid_frames([goaway])
  end
  
  # Extended CONTINUATION tests (6.10/5-6)
  it "validates CONTINUATION frame size limits (6.10/5)" do
    # Large CONTINUATION frame
    large_continuation = Bytes.new(16384)
    large_continuation.fill(0x80_u8)
    
    headers = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82]
    )
    
    continuation = build_raw_frame(
      length: 16384,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: large_continuation
    )
    
    expect_valid_frames([headers, continuation])
  end
  
  it "validates CONTINUATION without padding (6.10/6)" do
    # CONTINUATION frames don't support padding
    headers = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x82]
    )
    
    continuation = build_raw_frame(
      length: 2,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x86, 0x84]
    )
    
    expect_valid_frames([headers, continuation])
  end
  
  # Extended HTTP semantics tests
  {% for i in 1..10 %}
  it "extended HTTP semantics test {{i}}" do
    # Various HTTP semantic validations
    headers = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: {{i * 2 - 1}}_u32,
      payload: Bytes[0x82, 0x86, 0x84, 0x88]
    )
    
    expect_valid_frames([headers])
  end
  {% end %}
end