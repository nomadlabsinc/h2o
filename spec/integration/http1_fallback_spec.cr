require "../spec_helper"

describe "HTTP/1.1 Support" do
  it "verifies HTTP/2 protocol is used with nghttpd" do
    # Test with nghttpd (HTTP/2) server to ensure protocol detection works
    client = H2O::Client.new(timeout: TestConfig.client_timeout, verify_ssl: false)
    response = client.get("#{TestConfig.http2_url}/index.html")
    response.status.should eq(200)
    response.protocol.should eq("HTTP/2")
    response.body.should contain("HTTP/2")
    client.close
  end

  it "handles different response codes correctly" do
    client = H2O::Client.new(timeout: TestConfig.client_timeout, verify_ssl: false)

    # Test 404 response
    response = client.get("#{TestConfig.http2_url}/nonexistent")
    response.status.should eq(404)
    response.protocol.should eq("HTTP/2")

    client.close
  end
end
