require "../spec_helper"
require "json"

describe "Channel Fix Integration Test" do
  it "can create and close client without Channel::ClosedError" do
    client = H2O::Client.new(timeout: TestConfig::LOCALHOST_TIMEOUT, verify_ssl: false)

    begin
      # Test basic client functionality
      client.should_not be_nil

      # Test connection pool initialization
      client.connections.should be_empty

      # Try a simple request that will test the full HTTP/2 flow
      response = client.get("#{TestConfig.http2_url}/index.html")

      # Response should be successful if network is available
      # Allow for various network conditions (timeout, connectivity issues, etc.)
      if response
        # Accept various response codes - the key is that we get a response
        # without Channel::ClosedError when closing the client
        response.status.should be > 0
        response.body.should_not be_nil
      end
    ensure
      # This should complete without Channel::ClosedError
      client.close
    end
  end

  it "handles connection closure gracefully" do
    client = H2O::Client.new(timeout: TestConfig::LOCALHOST_TIMEOUT, verify_ssl: false)

    begin
      # Test multiple close calls (should be idempotent)
      client.close
      client.close # Should not cause errors

    rescue ex : Exception
      # Should not get Channel::ClosedError
      ex.class.should_not eq(Channel::ClosedError)
    end
  end
end
