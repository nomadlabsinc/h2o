require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC RST_STREAM Frames Compliance (Section 6.4)" do
  # Test for 6.4/1: Sends a RST_STREAM frame with 0x0 stream identifier
  it "sends a RST_STREAM frame with 0x0 stream identifier and expects a connection error" do
    mock_socket, client = create_mock_client

    # RST_STREAM frame on stream 0 (connection stream)
    rst_payload = build_rst_stream_payload(ERROR_CANCEL)

    rst_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: rst_payload
    )

    mock_socket.write(rst_frame)
    mock_socket.rewind

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.4/2: Sends a RST_STREAM frame with a length other than 4 octets
  it "sends a RST_STREAM frame with invalid length and expects a frame size error" do
    mock_socket, client = create_mock_client

    # RST_STREAM frame with wrong length (should be 4)
    rst_frame = build_raw_frame(
      length: 3, # Invalid - should be 4
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x00, 0x00, 0x08] # Only 3 bytes
    )

    mock_socket.write(rst_frame)
    mock_socket.rewind

    expect_raises(H2O::FrameSizeError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.4/3: Sends a RST_STREAM frame on a idle stream
  it "sends a RST_STREAM frame on an idle stream and expects a connection error" do
    mock_socket, client = create_mock_client

    # RST_STREAM frame on stream 3 which hasn't been opened
    rst_payload = build_rst_stream_payload(ERROR_CANCEL)

    rst_frame = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 3_u32,
      payload: rst_payload
    )

    mock_socket.write(rst_frame)
    mock_socket.rewind

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end
end
