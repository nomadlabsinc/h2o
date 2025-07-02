require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC CONTINUATION Frames Compliance (Section 6.10)" do
  # Test for 6.10/1: Sends a CONTINUATION frame without a preceding HEADERS frame
  it "sends a CONTINUATION frame without HEADERS and expects a connection error" do
    # CONTINUATION frame without preceding HEADERS
    continuation_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: "test".to_slice
    )
    
    expect_protocol_error([continuation_frame], H2O::ConnectionError, "CONTINUATION without HEADERS")
  end
  
  # Test for 6.10/2: Sends a CONTINUATION frame with a stream identifier of 0x0
  it "sends a CONTINUATION frame on connection stream and expects a connection error" do
    # First send HEADERS without END_HEADERS
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Then CONTINUATION on stream 0
    continuation_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 0_u32,
      payload: Bytes[0x41, 0x0f, 0x77]
    )
    
    expect_protocol_error([headers_frame, continuation_frame], H2O::ConnectionError, "CONTINUATION frame on connection stream")
  end
  
  # Test for 6.10/3: Sends a CONTINUATION frame on a different stream
  it "sends a CONTINUATION frame on different stream and expects a connection error" do
    # First send HEADERS without END_HEADERS on stream 1
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Then CONTINUATION on stream 3 (different stream)
    continuation_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 3_u32,
      payload: Bytes[0x41, 0x0f, 0x77]
    )
    
    expect_protocol_error([headers_frame, continuation_frame], H2O::ConnectionError, "CONTINUATION on different stream")
  end
  
  # Test for 6.10/4: Sends a frame other than CONTINUATION after HEADERS without END_HEADERS
  it "sends non-CONTINUATION frame after HEADERS without END_HEADERS and expects error" do
    # First send HEADERS without END_HEADERS
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Then send DATA frame instead of CONTINUATION
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: "test".to_slice
    )
    
    expect_protocol_error([headers_frame, data_frame], H2O::ConnectionError, "Expected CONTINUATION but got frame type")
  end
  
  # Test for valid CONTINUATION sequence
  it "sends valid HEADERS and CONTINUATION sequence" do
    # HEADERS without END_HEADERS
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # CONTINUATION with END_HEADERS
    continuation_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x41, 0x0f, 0x77]
    )
    
    # Should not raise error for valid sequence
    expect_valid_frames([headers_frame, continuation_frame])
  end
  
  # Test for multiple CONTINUATION frames
  it "sends multiple CONTINUATION frames in sequence" do
    # HEADERS without END_HEADERS
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # First CONTINUATION without END_HEADERS
    continuation1_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_CONTINUATION,
      flags: 0_u8,  # No END_HEADERS
      stream_id: 1_u32,
      payload: Bytes[0x41, 0x0f, 0x77]
    )
    
    # Second CONTINUATION with END_HEADERS
    continuation2_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x77, 0x77, 0x77]
    )
    
    # Should not raise error for valid sequence
    expect_valid_frames([headers_frame, continuation1_frame, continuation2_frame])
  end
end