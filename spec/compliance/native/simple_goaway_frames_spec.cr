require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC GOAWAY Frames Compliance (Section 6.8)" do
  # Test for 6.8/1: Sends a GOAWAY frame with a stream identifier other than 0x0
  it "sends a GOAWAY frame with non-zero stream identifier and expects a connection error" do
    # GOAWAY frame on stream 1 (should be stream 0)
    goaway_payload = build_goaway_payload(
      last_stream_id: 3_u32,
      error_code: ERROR_NO_ERROR,
      debug_data: "closing connection"
    )
    
    goaway_frame = build_raw_frame(
      length: goaway_payload.size,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: goaway_payload
    )
    
    expect_protocol_error([goaway_frame], H2O::ConnectionError, "GOAWAY frame on non-zero stream")
  end
  
  # Test for valid GOAWAY frame
  it "sends a valid GOAWAY frame and expects success" do
    # Valid GOAWAY frame
    goaway_payload = build_goaway_payload(
      last_stream_id: 0_u32,
      error_code: ERROR_NO_ERROR
    )
    
    goaway_frame = build_raw_frame(
      length: goaway_payload.size,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: goaway_payload
    )
    
    # Should not raise error for valid GOAWAY
    expect_valid_frames([goaway_frame])
  end
  
  # Test for GOAWAY with debug data
  it "sends a GOAWAY frame with debug data and expects success" do
    # GOAWAY frame with debug information
    goaway_payload = build_goaway_payload(
      last_stream_id: 5_u32,
      error_code: ERROR_PROTOCOL_ERROR,
      debug_data: "Protocol violation detected"
    )
    
    goaway_frame = build_raw_frame(
      length: goaway_payload.size,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: goaway_payload
    )
    
    # Should not raise error for valid GOAWAY with debug data
    expect_valid_frames([goaway_frame])
  end
end