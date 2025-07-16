require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC SETTINGS Frames Compliance (Section 6.5)" do
  # Test for 6.5/1: Sends a SETTINGS frame with a stream identifier other than 0x0
  it "sends a SETTINGS frame with non-zero stream identifier and expects a connection error" do
    mock_socket, client = create_mock_client

    # SETTINGS frame on stream 1 (should be stream 0)
    settings_payload = build_settings_payload({
      SETTINGS_MAX_CONCURRENT_STREAMS => 100_u32,
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::ConnectionError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5/2: Sends a SETTINGS frame with a length other than a multiple of 6 octets
  it "sends a SETTINGS frame with invalid length and expects a frame size error" do
    mock_socket, client = create_mock_client

    # SETTINGS frame with length not multiple of 6
    settings_frame = build_raw_frame(
      length: 5, # Invalid - should be multiple of 6
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes[0x00, 0x03, 0x00, 0x00, 0x64] # 5 bytes
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::FrameSizeError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5/3: Sends a SETTINGS frame with ACK flag and non-empty payload
  it "sends a SETTINGS frame with ACK flag and payload and expects a frame size error" do
    mock_socket, client = create_mock_client

    # SETTINGS frame with ACK flag and payload (invalid)
    settings_payload = build_settings_payload({
      SETTINGS_MAX_CONCURRENT_STREAMS => 100_u32,
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: FLAG_ACK,
      stream_id: 0_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::FrameSizeError) do
      client.request("GET", "/")
    end

    client.close
  end
end

describe "H2SPEC SETTINGS Parameters Compliance (Section 6.5.2)" do
  # Test for 6.5.2/1: Sends a SETTINGS_ENABLE_PUSH with a value other than 0 or 1
  it "sends SETTINGS_ENABLE_PUSH with invalid value and expects a protocol error" do
    mock_socket, client = create_mock_client

    # SETTINGS with invalid ENABLE_PUSH value
    settings_payload = build_settings_payload({
      SETTINGS_ENABLE_PUSH => 2_u32, # Invalid - must be 0 or 1
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::ProtocolError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5.2/2: Sends a SETTINGS_INITIAL_WINDOW_SIZE with a value above the maximum
  it "sends SETTINGS_INITIAL_WINDOW_SIZE above maximum and expects a flow control error" do
    mock_socket, client = create_mock_client

    # SETTINGS with INITIAL_WINDOW_SIZE > 2^31-1
    settings_payload = build_settings_payload({
      SETTINGS_INITIAL_WINDOW_SIZE => 0x80000000_u32, # 2^31 (too large)
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::FlowControlError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5.2/3: Sends a SETTINGS_MAX_FRAME_SIZE with a value below the minimum
  it "sends SETTINGS_MAX_FRAME_SIZE below minimum and expects a protocol error" do
    mock_socket, client = create_mock_client

    # SETTINGS with MAX_FRAME_SIZE < 16384
    settings_payload = build_settings_payload({
      SETTINGS_MAX_FRAME_SIZE => 16383_u32, # Below minimum
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::ProtocolError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5.2/4: Sends a SETTINGS_MAX_FRAME_SIZE with a value above the maximum
  it "sends SETTINGS_MAX_FRAME_SIZE above maximum and expects a protocol error" do
    mock_socket, client = create_mock_client

    # SETTINGS with MAX_FRAME_SIZE > 2^24-1
    settings_payload = build_settings_payload({
      SETTINGS_MAX_FRAME_SIZE => 0x01000000_u32, # 2^24
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings_payload
    )

    mock_socket.write(settings_frame)
    mock_socket.rewind

    expect_raises(H2O::ProtocolError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 6.5.2/5: Sends a SETTINGS frame with unknown identifier
  it "sends SETTINGS frame with unknown identifier and expects it to be ignored" do
    mock_socket = IO::Memory.new
    client = MockH2Client.new(mock_socket)

    # Initial settings
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)

    # SETTINGS with unknown identifier
    settings_payload = build_settings_payload({
      0xFF_u16 => 12345_u32, # Unknown setting ID
    })

    settings_frame = build_raw_frame(
      length: settings_payload.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings_payload
    )
    mock_socket.write(settings_frame)

    # Valid response to ensure client continues
    encoder = H2O::HPACK::Encoder.new
    response_headers = H2O::HeadersFrame.new(
      1,
      encoder.encode(H2O::Headers{":status" => "200"}),
      FLAG_END_HEADERS | FLAG_END_STREAM
    )
    mock_socket.write(response_headers.to_bytes)

    mock_socket.rewind

    # Should process normally, ignoring unknown setting
    response = client.get("https://example.com/")
    response.status.should eq(200)

    client.close
  end
end

describe "H2SPEC SETTINGS Synchronization Compliance (Section 6.5.3)" do
  # Test for 6.5.3/1: Sends multiple values of SETTINGS_INITIAL_WINDOW_SIZE
  it "sends multiple SETTINGS_INITIAL_WINDOW_SIZE values" do
    mock_socket = IO::Memory.new
    client = MockH2Client.new(mock_socket)

    # Initial settings
    mock_socket.write(H2O::Preface.create_initial_settings.to_bytes)

    # First SETTINGS with INITIAL_WINDOW_SIZE
    settings1 = build_settings_payload({
      SETTINGS_INITIAL_WINDOW_SIZE => 100_u32,
    })
    settings_frame1 = build_raw_frame(
      length: settings1.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings1
    )
    mock_socket.write(settings_frame1)

    # Second SETTINGS with different INITIAL_WINDOW_SIZE
    settings2 = build_settings_payload({
      SETTINGS_INITIAL_WINDOW_SIZE => 200_u32,
    })
    settings_frame2 = build_raw_frame(
      length: settings2.size,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: settings2
    )
    mock_socket.write(settings_frame2)

    # Valid response
    encoder = H2O::HPACK::Encoder.new
    response_headers = H2O::HeadersFrame.new(
      1,
      encoder.encode(H2O::Headers{":status" => "200"}),
      FLAG_END_HEADERS | FLAG_END_STREAM
    )
    mock_socket.write(response_headers.to_bytes)

    mock_socket.rewind

    # Should handle multiple settings updates
    response = client.get("https://example.com/")
    response.status.should eq(200)

    client.close
  end
end
