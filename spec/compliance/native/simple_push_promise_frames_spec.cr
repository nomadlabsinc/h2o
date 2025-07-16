require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC PUSH_PROMISE Frames Compliance (Section 6.6)" do
  # Test for 6.6/1: Sends a PUSH_PROMISE frame with a stream identifier of 0x0
  it "sends a PUSH_PROMISE frame on connection stream and expects a connection error" do
    # PUSH_PROMISE frame on stream 0 (connection stream)
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02, # Promised Stream ID: 2
      0x82, 0x86, 0x84        # HPACK data
    ]

    push_frame = build_raw_frame(
      length: push_promise_payload.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 0_u32,
      payload: push_promise_payload
    )

    expect_protocol_error([push_frame], H2O::ConnectionError, "PUSH_PROMISE frame on connection stream")
  end

  # Test for 6.6/2: Sends a PUSH_PROMISE frame with invalid promised stream ID
  it "sends a valid PUSH_PROMISE frame" do
    # Valid PUSH_PROMISE frame
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02, # Promised Stream ID: 2
      0x82, 0x86, 0x84        # HPACK data
    ]

    push_frame = build_raw_frame(
      length: push_promise_payload.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: push_promise_payload
    )

    # Should not raise error for valid PUSH_PROMISE
    expect_valid_frames([push_frame])
  end

  # Test for PUSH_PROMISE without END_HEADERS requiring CONTINUATION
  it "sends PUSH_PROMISE without END_HEADERS followed by CONTINUATION" do
    # PUSH_PROMISE without END_HEADERS
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02, # Promised Stream ID: 2
      0x82, 0x86              # Partial HPACK data
    ]

    push_frame = build_raw_frame(
      length: push_promise_payload.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: 0_u8, # No END_HEADERS
      stream_id: 1_u32,
      payload: push_promise_payload
    )

    # CONTINUATION with END_HEADERS
    continuation_frame = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x84] # Rest of HPACK data
    )

    # Should not raise error for valid sequence
    expect_valid_frames([push_frame, continuation_frame])
  end

  # Test for PUSH_PROMISE with padding (if PADDED flag is supported)
  it "sends PUSH_PROMISE frame with too small payload" do
    # PUSH_PROMISE with insufficient payload (less than 4 bytes for promised stream ID)
    push_frame = build_raw_frame(
      length: 3, # Too small - needs at least 4 bytes
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x00, 0x00, 0x00]
    )

    expect_protocol_error([push_frame], H2O::FrameSizeError, "PUSH_PROMISE frame too small")
  end
end
