require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC Frame Size Compliance" do
  # Test for 4.2/1: Sends a DATA frame with 2^14 octets in length
  it "sends a DATA frame with 2^14 octets in length and expects success" do
    # First send HEADERS to open stream 1
    encoder = H2O::HPACK::Encoder.new
    headers_payload = encoder.encode(H2O::Headers{":status" => "200"})
    headers_frame = build_raw_frame(
      headers_payload.size,
      FRAME_TYPE_HEADERS,
      FLAG_END_HEADERS,
      1_u32,
      headers_payload
    )

    # Then DATA frame with length 16384 (2^14)
    data_payload = Bytes.new(16384)
    data_frame = build_raw_frame(16384, FRAME_TYPE_DATA, FLAG_END_STREAM, 1_u32, data_payload)

    mock_socket, client = create_mock_client_with_frames([headers_frame, data_frame])

    # The mock client should process both frames without error
    response = client.request("GET", "/")
    response.should_not be_nil
    client.close
  end

  # Test for 4.2/2: Sends a DATA frame that exceeds SETTINGS_MAX_FRAME_SIZE
  it "sends a DATA frame that exceeds SETTINGS_MAX_FRAME_SIZE and expects a connection error" do
    # First create a mock client
    mock_socket = IO::Memory.new
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)

    # Send a SETTINGS frame that sets MAX_FRAME_SIZE to 16384
    settings_payload = build_settings_payload({SETTINGS_MAX_FRAME_SIZE => 16384_u32})
    settings_frame = build_raw_frame(settings_payload.size, FRAME_TYPE_SETTINGS, 0_u8, 0_u32, settings_payload)
    mock_socket.write(settings_frame)

    # Then send a DATA frame of size 16385 (exceeds the limit)
    # Note: We can't actually create a frame > 16384 in the header without lying about the length
    oversized_frame = Bytes[
      0x00, 0x40, 0x01,      # Length: 16385
      FRAME_TYPE_DATA,       # Type: DATA
      0x00,                  # Flags: none
      0x00, 0x00, 0x00, 0x01 # Stream ID: 1
    # Payload would follow but we're just testing the header
    ]
    mock_socket.write(oversized_frame)
    mock_socket.rewind

    client = MockH2Client.new(mock_socket)

    expect_raises(H2O::FrameSizeError, "Frame size 16385 exceeds max 16384") do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 4.2/3: Sends a HEADERS frame that exceeds SETTINGS_MAX_FRAME_SIZE
  it "sends a HEADERS frame that exceeds SETTINGS_MAX_FRAME_SIZE and expects a connection error" do
    # Similar to above but with HEADERS frame
    mock_socket = IO::Memory.new
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)

    # Send a SETTINGS frame that sets MAX_FRAME_SIZE to 16384
    settings_payload = build_settings_payload({SETTINGS_MAX_FRAME_SIZE => 16384_u32})
    settings_frame = build_raw_frame(settings_payload.size, FRAME_TYPE_SETTINGS, 0_u8, 0_u32, settings_payload)
    mock_socket.write(settings_frame)

    # HEADERS frame claiming to be 16385 bytes
    oversized_headers = Bytes[
      0x00, 0x40, 0x01,      # Length: 16385
      FRAME_TYPE_HEADERS,    # Type: HEADERS
      FLAG_END_HEADERS,      # Flags: END_HEADERS
      0x00, 0x00, 0x00, 0x01 # Stream ID: 1
    ]
    mock_socket.write(oversized_headers)
    mock_socket.rewind

    client = MockH2Client.new(mock_socket)

    expect_raises(H2O::FrameSizeError, "Frame size 16385 exceeds max 16384") do
      client.request("GET", "/")
    end

    client.close
  end
end
