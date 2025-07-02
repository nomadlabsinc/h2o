require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC DATA Frames Compliance (Section 6.1)" do
  # Test for 6.1/1: Sends a DATA frame with 0x0 stream identifier
  it "sends a DATA frame with 0x0 stream identifier and expects a connection error" do
    # DATA frame on stream 0 (connection stream)
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: "test".to_slice
    )
    
    expect_protocol_error([data_frame], H2O::ConnectionError, "DATA frame on connection stream")
  end
  
  # Test for 6.1/2: Sends a DATA frame on a stream in the half-closed (local) state
  it "sends a DATA frame on a stream in half-closed (local) state and expects no error" do
    # This test validates that DATA frames are allowed from server to client
    # when stream is half-closed (local) - i.e., client sent END_STREAM
    
    # First open stream with HEADERS + END_STREAM to make it half-closed (local)
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Server sends DATA frame on stream 1 (valid scenario)
    data_frame = build_raw_frame(
      length: 13,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: "response data".to_slice
    )
    
    # Should not raise error
    expect_valid_frames([headers, data_frame])
  end
  
  # Test for 6.1/3: Sends a DATA frame with invalid pad length
  it "sends a DATA frame with invalid pad length and expects a connection error" do
    # First open the stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # DATA frame with PADDED flag and pad length > payload length
    padded_data = Bytes[
      0xFF, # Pad Length: 255 (exceeds frame length)
      0x01, 0x02, 0x03, 0x04 # Actual data (4 bytes)
    ]
    
    data_frame = build_raw_frame(
      length: 5,
      type: FRAME_TYPE_DATA,
      flags: FLAG_PADDED,
      stream_id: 1_u32,
      payload: padded_data
    )
    
    # Validate the headers frame first, then expect error on data frame
    validator = H2O::MockH2Validator.new
    validator.validate_frames([headers])
    
    expect_raises(H2O::ProtocolError, "Invalid pad length") do
      validator.validate_frames([data_frame])
    end
  end
end