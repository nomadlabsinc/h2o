require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC RST_STREAM Frames Compliance (Section 6.4)" do
  # Test for 6.4/1: Sends a RST_STREAM frame with 0x0 stream identifier
  it "sends a RST_STREAM frame with 0x0 stream identifier and expects a connection error" do
    # RST_STREAM frame on stream 0 (connection stream)
    rst_payload = build_rst_stream_payload(ERROR_CANCEL)
    
    rst_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: rst_payload
    )
    
    expect_protocol_error([rst_frame], H2O::ConnectionError, "RST_STREAM frame on connection stream")
  end
  
  # Test for 6.4/2: Sends a RST_STREAM frame with a length other than 4 octets
  it "sends a RST_STREAM frame with invalid length and expects a frame size error" do
    # RST_STREAM frame with wrong length (should be 4)
    rst_frame = build_raw_frame(
      length: 3, # Invalid - should be 4
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x00, 0x00, 0x08] # Only 3 bytes
    )
    
    expect_protocol_error([rst_frame], H2O::FrameSizeError, "RST_STREAM frame must be 4 octets")
  end
  
  # Test for 6.4/3: Sends a RST_STREAM frame on an idle stream
  it "sends a RST_STREAM frame on an idle stream and expects a connection error" do
    # RST_STREAM frame on stream 3 which hasn't been opened
    rst_payload = build_rst_stream_payload(ERROR_CANCEL)
    
    rst_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 3_u32,
      payload: rst_payload
    )
    
    expect_protocol_error([rst_frame], H2O::ConnectionError, "RST_STREAM on idle stream")
  end
end