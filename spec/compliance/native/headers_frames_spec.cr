require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC HEADERS Frames Compliance (Section 6.2)" do
  # Test for 6.2/1: Sends a HEADERS frame with 0x0 stream identifier
  it "sends a HEADERS frame with 0x0 stream identifier and expects a connection error" do
    mock_socket, client = create_mock_client

    # HEADERS frame on stream 0 (connection stream)
    encoder = H2O::HPACK::Encoder.new
    headers_payload = encoder.encode(H2O::Headers{":status" => "200"})
    headers_frame = build_raw_frame(
      length: headers_payload.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 0_u32,
      payload: headers_payload
    )

    mock_socket.write(headers_frame)
    mock_socket.rewind

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.2/2: Sends a HEADERS frame with invalid pad length
  it "sends a HEADERS frame with invalid pad length and expects a connection error" do
    # HEADERS frame with PADDED flag and pad length > payload length
    encoder = H2O::HPACK::Encoder.new
    headers_data = encoder.encode(H2O::Headers{":status" => "200"})
    padded_payload = Bytes.new(1 + headers_data.size)
    padded_payload[0] = 0xFF_u8 # Pad Length: 255 (exceeds frame length)
    headers_data.copy_to(padded_payload + 1)

    headers_frame = build_raw_frame(
      padded_payload.size,
      FRAME_TYPE_HEADERS,
      FLAG_PADDED | FLAG_END_HEADERS,
      1_u32,
      padded_payload
    )

    mock_socket, client = create_mock_client_with_frames([headers_frame])

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.2/3: Sends a HEADERS frame that contains a invalid header block fragment
  it "sends a HEADERS frame with invalid header block and expects a compression error" do
    mock_socket, client = create_mock_client

    # Invalid HPACK data (random bytes that don't form valid HPACK)
    invalid_hpack = Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    headers_frame = build_raw_frame(
      length: invalid_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: invalid_hpack
    )

    mock_socket.write(headers_frame)
    mock_socket.rewind

    expect_raises(H2O::CompressionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.2/4: Sends a HEADERS frame that contains the connection-specific header field
  it "sends a HEADERS frame with connection-specific header and expects a protocol error" do
    # Headers with forbidden Connection header
    encoder = H2O::HPACK::Encoder.new
    headers_with_connection = encoder.encode(H2O::Headers{
      ":status"    => "200",
      "connection" => "keep-alive",
    })

    headers_frame = build_raw_frame(
      headers_with_connection.size,
      FRAME_TYPE_HEADERS,
      FLAG_END_HEADERS | FLAG_END_STREAM,
      1_u32,
      headers_with_connection
    )

    mock_socket, client = create_mock_client_with_frames([headers_frame])

    expect_raises(H2O::ProtocolError) do
      client.request("GET", "/")
    end

    client.close
  end
end
