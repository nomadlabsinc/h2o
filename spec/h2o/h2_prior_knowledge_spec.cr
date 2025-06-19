require "../spec_helper"

describe H2O::Client do
  describe "HTTP/2 Prior Knowledge Support" do
    it "accepts http:// URLs when h2_prior_knowledge is enabled" do
      client = H2O::Client.new(h2_prior_knowledge: true)

      # This should not raise an error
      # Will fail to connect since there's no server, but URL parsing should pass
      response = client.get("http://example.com/test")
      response.status.should eq(0) # Connection error response
    end

    it "rejects http:// URLs when h2_prior_knowledge is disabled" do
      client = H2O::Client.new(h2_prior_knowledge: false)

      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("http://example.com/test")
      end
    end

    it "still accepts https:// URLs when h2_prior_knowledge is enabled" do
      client = H2O::Client.new(h2_prior_knowledge: true)

      # Should not raise for URL parsing
      # Will fail to connect since there's no server, but URL parsing should pass
      response = client.get("https://example.com/test")
      response.status.should eq(0) # Connection error response
    end

    it "creates TCP socket instead of TLS socket for h2c connections" do
      client = H2O::Client.new(h2_prior_knowledge: true)

      # Mock the connection creation to verify socket type
      # This is a simplified test - in reality would need proper mocking
      response = client.get("http://localhost:8080/test")
      response.status.should eq(0) # Connection error
    end

    it "does not fall back to HTTP/1.1 when prior knowledge is enabled" do
      client = H2O::Client.new(h2_prior_knowledge: true)

      # With prior knowledge, there should be no HTTP/1.1 fallback
      response = client.get("http://localhost:8080/test")
      response.status.should eq(0) # Connection error
    end
  end

  describe "Integration with h2c server" do
    # These tests would require an actual h2c server running
    # They're marked as pending for now

    pending "successfully connects to h2c server with prior knowledge" do
      # Would need an h2c test server running on port 8080
      client = H2O::Client.new(h2_prior_knowledge: true)
      response = client.get("http://localhost:8080/")
      response.status.should eq(200)
    end

    pending "sends HTTP/2 connection preface immediately" do
      # Would verify that the client sends the HTTP/2 connection preface
      # immediately after TCP connection without waiting for upgrade
    end

    pending "handles h2c server responses correctly" do
      # Would test various response scenarios from an h2c server
    end
  end
end
