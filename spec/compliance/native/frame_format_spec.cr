require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC Frame Format Compliance" do
  # Test for 4.1/1: Sends a frame with an unknown type.
  it "sends a frame with an unknown type and expects it to be ignored" do
    # Frame with unknown type 0x99
    unknown_frame = build_raw_frame(1, 0x99_u8, 0_u8, 1_u32, Bytes[0xFF])
    
    # A valid response to a GET request
    encoder = H2O::HPACK::Encoder.new
    response_headers = H2O::HeadersFrame.new(1, encoder.encode(H2O::Headers{":status" => "200"}), H2O::HeadersFrame::FLAG_END_HEADERS | H2O::HeadersFrame::FLAG_END_STREAM)
    
    # Create mock client with unknown frame followed by valid response
    mock_socket, client = create_mock_client_with_frames([unknown_frame, response_headers.to_bytes])

    response = client.get("https://example.com/")
    response.status.should eq(200)
    client.close
  end

  # Test for 4.1/2: Sends a frame with a length that exceeds the max.
  it "sends a frame with a length that exceeds the max and expects a connection error" do
    # Frame with length > MAX_FRAME_SIZE (16384)
    # Note: We can't actually create a payload > 16384 in the header, but we can fake it
    exceeds_max_frame = Bytes[
      0x00, 0x40, 0x01, # Length: 16385
      0x00,             # Type: DATA
      0x00,             # Flags: none
      0x00, 0x00, 0x00, 0x01 # Stream ID: 1
    ]

    mock_socket, client = create_mock_client_with_frames([exceeds_max_frame])

    # The mock client will fail trying to read the oversized frame
    expect_raises(H2O::FrameSizeError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 4.1/3: Sends a frame with invalid pad length.
  it "sends a frame with invalid pad length and expects a connection error" do
    # DATA frame with PADDED flag, but pad length > frame payload length
    # Total length is 8, pad length is 10 (invalid)
    invalid_padded_frame = Bytes[
      0x00, 0x00, 0x08, # Length: 8
      FRAME_TYPE_DATA,  # Type: DATA
      FLAG_PADDED,      # Flags: PADDED
      0x00, 0x00, 0x00, 0x01, # Stream ID: 1
      0x0A,             # Pad Length: 10 (invalid, > 8)
      0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
    ]

    mock_socket, client = create_mock_client_with_frames([invalid_padded_frame])

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end
end
