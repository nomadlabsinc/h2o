require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC DATA Frames Compliance (Section 6.1)" do
  # Test for 6.1/1: Sends a DATA frame with 0x0 stream identifier
  it "sends a DATA frame with 0x0 stream identifier and expects a connection error" do
    mock_socket, client = create_mock_client

    # DATA frame on stream 0 (connection stream)
    data_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: "test".to_slice
    )

    mock_socket.write(data_frame)
    mock_socket.rewind

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.1/2: Sends a DATA frame on a stream in the half-closed (local) state
  it "sends a DATA frame on a stream in half-closed (local) state and expects no error" do
    mock_socket = IO::Memory.new
    client = MockH2Client.new(mock_socket)

    # Client sends request with END_STREAM (half-closed local)
    request_headers = {
      ":method"    => "GET",
      ":path"      => "/",
      ":scheme"    => "https",
      ":authority" => "example.com",
    }

    # Manually construct response to control timing
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)

    # Server sends HEADERS without END_STREAM
    encoder = H2O::HPACK::Encoder.new
    response_headers = H2O::HeadersFrame.new(
      1,
      encoder.encode(H2O::Headers{":status" => "200"}),
      FLAG_END_HEADERS
    )
    mock_socket.write(response_headers.to_bytes)

    # Server sends DATA frames (valid in half-closed local)
    data_frame = H2O::DataFrame.new(1, "response data".to_slice)
    mock_socket.write(data_frame.to_bytes)

    # Server ends stream
    end_frame = H2O::DataFrame.new(1, Bytes.empty, FLAG_END_STREAM)
    mock_socket.write(end_frame.to_bytes)

    mock_socket.rewind

    # Should complete successfully
    response = client.get("https://example.com/")
    response.status.should eq(200)

    client.close
  end

  # Test for 6.1/3: Sends a DATA frame with invalid pad length
  it "sends a DATA frame with invalid pad length and expects a connection error" do
    # DATA frame with PADDED flag and pad length > payload length
    padded_data = Bytes[
      0xFF,                  # Pad Length: 255 (exceeds frame length)
      0x01, 0x02, 0x03, 0x04 # Actual data (4 bytes)
    ]

    data_frame = build_raw_frame(
      5,
      FRAME_TYPE_DATA,
      FLAG_PADDED,
      1_u32,
      padded_data
    )

    mock_socket, client = create_mock_client_with_frames([data_frame])

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end
end
