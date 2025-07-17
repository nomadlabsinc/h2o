require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC WINDOW_UPDATE Frames Compliance (Section 6.9)" do
  # Test for 6.9/1: Sends a WINDOW_UPDATE frame with a length other than 4 octets
  it "sends a WINDOW_UPDATE frame with invalid length and expects a frame size error" do
    # WINDOW_UPDATE frame with wrong length (should be 4)
    window_frame = build_raw_frame(
      length: 3, # Invalid - should be 4
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes[0x00, 0x00, 0x01] # Only 3 bytes
    )

    expect_protocol_error([window_frame], H2O::FrameSizeError, "WINDOW_UPDATE frame must be 4 octets")
  end

  # Test for 6.9/2: Sends a WINDOW_UPDATE frame with a flow control window increment of 0
  it "sends a WINDOW_UPDATE frame with increment of 0 on connection and expects a connection error" do
    # WINDOW_UPDATE frame with 0 increment on connection stream
    window_payload = build_window_update_payload(0_u32)

    window_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: window_payload
    )

    expect_protocol_error([window_frame], H2O::ConnectionError, "WINDOW_UPDATE increment of 0 on connection")
  end

  # Test for 6.9/3: Sends a WINDOW_UPDATE frame with a flow control window increment of 0 on a stream
  it "sends a WINDOW_UPDATE frame with increment of 0 on stream and expects a stream error" do
    # WINDOW_UPDATE frame with 0 increment on stream
    window_payload = build_window_update_payload(0_u32)

    window_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: window_payload
    )

    expect_protocol_error([window_frame], H2O::StreamError, "WINDOW_UPDATE increment of 0 on stream")
  end

  # Test for valid WINDOW_UPDATE frame
  it "sends a valid WINDOW_UPDATE frame and expects success" do
    # Valid WINDOW_UPDATE frame
    window_payload = build_window_update_payload(1000_u32)

    window_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: window_payload
    )

    # Should not raise error for valid WINDOW_UPDATE
    expect_valid_frames([window_frame])
  end
end

describe "H2SPEC Flow Control Compliance (Section 6.9.1)" do
  # Test for maximum window size
  it "sends a WINDOW_UPDATE with maximum allowed increment" do
    # Maximum window increment (2^31 - 1)
    window_payload = build_window_update_payload(0x7FFFFFFF_u32)

    window_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: window_payload
    )

    # Should not raise error for maximum valid increment
    expect_valid_frames([window_frame])
  end
end
