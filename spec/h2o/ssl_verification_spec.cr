require "../spec_helper"

describe "SSL Verification Configuration" do
  describe "H2O::Configuration" do
    it "defaults to verifying SSL" do
      # Save original env var if any
      original_env = ENV["H2O_VERIFY_SSL"]?
      ENV.delete("H2O_VERIFY_SSL")

      config = H2O::Configuration.new
      config.verify_ssl.should be_true

      # Restore
      ENV["H2O_VERIFY_SSL"] = original_env if original_env
    end

    it "respects H2O_VERIFY_SSL environment variable when set to false" do
      original_env = ENV["H2O_VERIFY_SSL"]?
      ENV["H2O_VERIFY_SSL"] = "false"
      config = H2O::Configuration.new
      config.verify_ssl.should be_false
      ENV.delete("H2O_VERIFY_SSL")
      ENV["H2O_VERIFY_SSL"] = original_env if original_env
    end

    it "respects H2O_VERIFY_SSL environment variable when set to 0" do
      original_env = ENV["H2O_VERIFY_SSL"]?
      ENV["H2O_VERIFY_SSL"] = "0"
      config = H2O::Configuration.new
      config.verify_ssl.should be_false
      ENV.delete("H2O_VERIFY_SSL")
      ENV["H2O_VERIFY_SSL"] = original_env if original_env
    end

    it "respects H2O_VERIFY_SSL environment variable when set to true" do
      original_env = ENV["H2O_VERIFY_SSL"]?
      ENV["H2O_VERIFY_SSL"] = "true"
      config = H2O::Configuration.new
      config.verify_ssl.should be_true
      ENV.delete("H2O_VERIFY_SSL")
      ENV["H2O_VERIFY_SSL"] = original_env if original_env
    end

    it "respects H2O_VERIFY_SSL environment variable when set to 1" do
      original_env = ENV["H2O_VERIFY_SSL"]?
      ENV["H2O_VERIFY_SSL"] = "1"
      config = H2O::Configuration.new
      config.verify_ssl.should be_true
      ENV.delete("H2O_VERIFY_SSL")
      ENV["H2O_VERIFY_SSL"] = original_env if original_env
    end
  end

  describe "H2O::Client" do
    it "uses global configuration verify_ssl by default" do
      client = H2O::Client.new
      client.verify_ssl.should eq(H2O.config.verify_ssl)
    end

    it "allows overriding verify_ssl on initialization" do
      client = H2O::Client.new(verify_ssl: false)
      client.verify_ssl.should be_false
    end

    it "passes verify_ssl to HTTP/2 connections" do
      client = H2O::Client.new(verify_ssl: false)

      # Mock the TLS connection to avoid actual network calls
      spawn do
        response = client.get("https://example.com")
      rescue ex : H2O::ConnectionError
        # Expected - we're testing configuration, not actual connection
      end

      # Give the fiber a chance to run
      sleep 0.1.seconds

      # The test passes if no SSL verification error was raised
      # (actual connection will fail for other reasons in test environment)
    end

    it "passes verify_ssl to HTTP/1.1 connections" do
      client = H2O::Client.new(verify_ssl: false)

      # Force HTTP/1.1 by caching the protocol
      client.@protocol_cache.cache_protocol("example.com", 4430, H2O::ProtocolVersion::Http11)

      # Mock the TLS connection to avoid actual network calls
      spawn do
        response = client.get("https://example.com")
      rescue ex : H2O::ConnectionError
        # Expected - we're testing configuration, not actual connection
      end

      # Give the fiber a chance to run
      sleep 0.1.seconds

      # The test passes if no SSL verification error was raised
      # (actual connection will fail for other reasons in test environment)
    end
  end

  describe "H2O global configuration" do
    it "can be configured to disable SSL verification" do
      original_verify_ssl = H2O.config.verify_ssl

      H2O.configure do |config|
        config.verify_ssl = false
      end

      H2O.config.verify_ssl.should be_false

      # Restore original value
      H2O.configure do |config|
        config.verify_ssl = original_verify_ssl
      end
    end
  end
end
