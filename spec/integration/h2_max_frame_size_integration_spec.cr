require "../spec_helper"

describe "H2O::H2::Client max_frame_size handling", tags: "integration" do
  it "handles large request bodies by fragmenting when exceeding max_frame_size" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Create a large body that exceeds default max_frame_size (16KB)
    large_body = "A" * 32768 # 32KB body

    response = client.request("POST", "/post", body: large_body)

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end

  it "handles large headers by fragmenting with CONTINUATION frames when exceeding max_frame_size" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Create large headers that exceed default max_frame_size
    large_headers = H2O::Headers.new
    # Add many large headers to exceed frame size limit
    100.times do |i|
      large_headers["custom-header-#{i}"] = "A" * 200 # Each header is ~200 bytes
    end

    response = client.request("GET", "/", headers: large_headers)

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end

  it "respects server's max_frame_size setting from SETTINGS frame" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Make initial request to establish connection and receive SETTINGS
    initial_response = client.request("GET", "/")
    initial_response.should_not be_nil
    initial_response.status.should eq(200)

    # Check that remote settings have been updated from server
    client.remote_settings.max_frame_size.should be >= 16384_u32 # Minimum HTTP/2 frame size

    # Send a request with body size close to but under max_frame_size
    test_body_size = (client.remote_settings.max_frame_size - 100).to_i
    test_body = "B" * test_body_size

    response = client.request("POST", "/post", body: test_body)

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end

  it "handles edge case where body size exactly equals max_frame_size" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Make initial request to get remote settings
    client.request("GET", "/")

    # Create body that exactly matches max_frame_size
    exact_body = "C" * client.remote_settings.max_frame_size.to_i

    response = client.request("POST", "/post", body: exact_body)

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end

  it "handles empty body requests correctly" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    response = client.request("POST", "/post", body: "")

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end

  it "handles very large bodies requiring multiple frame fragments" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Create a very large body (5x default max_frame_size)
    very_large_body = "D" * (16384 * 5) # 80KB body

    response = client.request("POST", "/post", body: very_large_body)

    response.should_not be_nil
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")

    client.close
  end
end
