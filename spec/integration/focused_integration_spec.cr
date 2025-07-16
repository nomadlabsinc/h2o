require "../spec_helper"

describe "H2O Focused Integration Tests" do
  describe "basic client operations" do
    it "can create and close clients safely" do
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      client.connections.should be_empty
      client.close
    end

    it "handles multiple close calls gracefully" do
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      client.close
      client.close # Should not cause segfault
    end

    it "handles requests after close gracefully" do
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      client.close

      # Should handle requests gracefully after close
      expect_raises(H2O::ConnectionError) do
        client.get("#{TestConfig.http2_url}/index.html")
      end
    end

    it "can perform basic HTTP validation" do
      # Skip network test if environment variable is set
      if ENV["SKIP_NETWORK_TESTS"]? == "true"
        pending("Network tests disabled")
      end

      client = H2O::Client.new(timeout: 5.seconds, verify_ssl: false)
      response = client.get("#{TestConfig.http2_url}/index.html")

      response.should_not be_nil
      response.status.should eq(200)
      client.close
    end
  end
end
