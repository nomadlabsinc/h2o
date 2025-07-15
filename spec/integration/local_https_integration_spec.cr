require "../spec_helper"
require "./support/http2_test_helpers_spec"

describe "Local HTTPS Integration Tests" do
  describe "HTTPS connectivity with local nghttpd server" do
    it "can connect to HTTPS endpoints with SSL verification disabled" do
      client = H2O::Client.new(verify_ssl: false)
      
      response = client.get(TestConfig.http2_url("/"))
      
      response.status.should be >= 200
      response.status.should be < 300
      response.headers["server"]?.should_not be_nil
      response.headers["server"].should contain("nghttpd")
      client.close
    end

    it "can handle HTTPS requests with custom headers" do
      client = H2O::Client.new(verify_ssl: false)
      
      headers = {
        "user-agent" => "h2o-crystal-client",
        "accept" => "text/html"
      }
      response = client.get(TestConfig.http2_url("/"), headers)
      
      response.status.should be >= 200
      response.status.should be < 300
      client.close
    end

    it "can perform POST requests over HTTPS" do
      client = H2O::Client.new(verify_ssl: false)
      
      headers = {
        "content-type" => "application/json"
      }
      body = "{\"test\": \"data\"}"
      response = client.post(TestConfig.http2_url("/"), body, headers)
      
      response.status.should be >= 200
      response.status.should be < 500  # nghttpd may return 404 for POST, which is fine
      client.close
    end
  end

  describe "HTTPS error handling" do
    it "handles connection timeout gracefully" do
      # Use invalid IP that will timeout
      client = H2O::Client.new(timeout: 1.seconds)
      response = client.get("https://10.255.255.1/")  # Non-routable IP - guaranteed to timeout
      
      # High-level client returns error response instead of raising
      response.error?.should be_true
      response.status.should eq(0)
      response.error.should_not be_nil
      response.error.not_nil!.should contain("Connection")
      client.close
    end

    it "handles SSL verification failures with self-signed certificates" do
      # nghttpd uses self-signed certificates, so this should fail with verify_ssl: true
      # Test the H2::Client directly to ensure SSL verification is enforced
      HTTP2TestHelpers.assert_ssl_verification_failure
    end

    it "handles invalid hostnames gracefully" do
      client = H2O::Client.new(timeout: 2.seconds)
      response = client.get("https://invalid-hostname-that-does-not-exist-12345.test/")
      
      # High-level client returns error response instead of raising
      response.error?.should be_true
      response.status.should eq(0)
      response.error.should_not be_nil
      client.close
    end
  end

  describe "SSL verification configuration" do
    it "respects verify_ssl: false configuration" do
      client = H2O::Client.new(verify_ssl: false)
      
      # Should succeed with self-signed cert
      response = client.get(TestConfig.http2_url("/"))
      response.status.should be >= 200
      response.status.should be < 300
      client.close
    end

    it "respects verify_ssl: true configuration" do
      # Test the H2::Client directly to ensure SSL verification is enforced
      HTTP2TestHelpers.assert_ssl_verification_failure
    end

    it "uses environment variable H2O_VERIFY_SSL setting" do
      # The docker-compose.yml sets H2O_VERIFY_SSL=false
      client = H2O::Client.new
      client.verify_ssl.should be_false
    end
  end
end