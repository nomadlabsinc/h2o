require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC PING Frames Compliance (Section 6.7)" do
  # Test for 6.7/1: Sends a PING frame with a stream identifier other than 0x0
  it "sends a PING frame with non-zero stream identifier and expects a connection error" do
    # PING frame on stream 1 (should be stream 0)
    ping_payload = build_ping_payload(0x1234567890ABCDEF_u64)

    ping_frame = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: ping_payload
    )

    expect_protocol_error([ping_frame], H2O::ConnectionError, "PING frame on non-zero stream")
  end

  # Test for 6.7/2: Sends a PING frame with a length other than 8 octets
  it "sends a PING frame with invalid length and expects a frame size error" do
    # PING frame with wrong length (should be 8)
    ping_frame = build_raw_frame(
      length: 6, # Invalid - should be 8
      type: FRAME_TYPE_PING,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes[0x00, 0x00, 0x00, 0x00, 0x00, 0x00] # Only 6 bytes
    )

    expect_protocol_error([ping_frame], H2O::FrameSizeError, "PING frame must be 8 octets")
  end

  # Test for 6.7/3: Sends a PING frame with ACK flag and valid data
  it "sends a PING frame with ACK flag and expects success" do
    # PING ACK frame (valid)
    ping_payload = build_ping_payload(0xDEADBEEF12345678_u64)

    ping_frame = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: FLAG_ACK,
      stream_id: 0_u32,
      payload: ping_payload
    )

    # Should not raise error for valid PING ACK
    expect_valid_frames([ping_frame])
  end

  # Test for 6.7/4: Sends a PING frame without ACK flag
  it "sends a PING frame without ACK flag and expects success" do
    # Regular PING frame (valid)
    ping_payload = build_ping_payload(0x0123456789ABCDEF_u64)

    ping_frame = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: ping_payload
    )

    # Should not raise error for valid PING
    expect_valid_frames([ping_frame])
  end
end
