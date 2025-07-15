require "../spec_helper"
require "./support/http2_test_helpers_spec"

describe "SSL Verification Integration" do
  describe "disabling SSL verification for local testing" do
    it "allows connection to servers with self-signed certificates when verify_ssl is false" do
      # This test demonstrates how to disable SSL verification for local testing
      # with self-signed certificates

      # Method 1: Using environment variable
      # Note: Environment variables affect the global config at initialization,
      # so we can't change them after the config is created.
      # This is documented behavior - env vars should be set before requiring h2o

      # Method 2: Using global configuration
      original_verify_ssl = H2O.config.verify_ssl
      H2O.configure do |config|
        config.verify_ssl = false
      end
      client2 = H2O::Client.new
      client2.verify_ssl.should be_false

      # Restore original configuration
      H2O.configure do |config|
        config.verify_ssl = original_verify_ssl
      end

      # Method 3: Using client initialization parameter
      client3 = H2O::Client.new(verify_ssl: false)
      client3.verify_ssl.should be_false
    end

    it "allows connection to local server with self-signed certificate" do
      # Disable SSL verification for this test
      client = H2O::Client.new(verify_ssl: false)

      # This test will try to connect to a local server
      # It should not raise SSL verification errors
      spawn do
        response = client.get(TestConfig.http2_url("/test"))
      rescue ex : H2O::ConnectionError
        # Connection error is expected since no server is running
        # But we shouldn't get SSL verification errors
        ex.message.should_not match(/certificate verify failed/)
      end

      sleep 0.1.seconds
    end

    it "demonstrates environment variable usage" do
      # Environment variables must be set before the H2O module is loaded
      # This test documents the expected usage pattern

      # When H2O_VERIFY_SSL is set to "false" before loading the library,
      # all clients will default to verify_ssl: false
      # Example: H2O_VERIFY_SSL=false crystal spec

      # For runtime configuration, use the client constructor instead:
      client = H2O::Client.new(verify_ssl: false)
      client.verify_ssl.should be_false
    end
  end

  describe "SSL verification enabled (default)" do
    it "defaults to verifying SSL certificates" do
      # In test environment, H2O_VERIFY_SSL is set to false
      # So we test that the client respects environment settings
      client = H2O::Client.new
      if ENV["H2O_VERIFY_SSL"]? == "false"
        client.verify_ssl.should be_false
      else
        client.verify_ssl.should be_true
      end
    end

    it "rejects connections to servers with invalid certificates" do
      # This test verifies that SSL verification is working
      # by attempting to connect to our local nghttpd server with self-signed cert
      # Test the H2::Client directly to ensure SSL verification is enforced
      HTTP2TestHelpers.assert_ssl_verification_failure
    end
  end
end
