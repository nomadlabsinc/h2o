require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC PRIORITY Frames Compliance (Section 6.3)" do
  # Test for 6.3/1: Sends a PRIORITY frame with 0x0 stream identifier
  it "sends a PRIORITY frame with 0x0 stream identifier and expects a connection error" do
    # PRIORITY frame on stream 0 (connection stream)
    priority_payload = build_priority_payload(
      stream_dependency: 1_u32,
      weight: 16_u8
    )
    
    priority_frame = build_raw_frame(
      length: 5,
      type: FRAME_TYPE_PRIORITY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: priority_payload
    )
    
    expect_protocol_error([priority_frame], H2O::ConnectionError, "PRIORITY frame on connection stream")
  end
  
  # Test for 6.3/2: Sends a PRIORITY frame with a length other than 5 octets
  it "sends a PRIORITY frame with invalid length and expects a frame size error" do
    # PRIORITY frame with wrong length (should be 5)
    priority_frame = build_raw_frame(
      length: 4, # Invalid - should be 5
      type: FRAME_TYPE_PRIORITY,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x00, 0x00, 0x00, 0x01] # Only 4 bytes
    )
    
    expect_protocol_error([priority_frame], H2O::FrameSizeError, "PRIORITY frame must be 5 octets")
  end
end