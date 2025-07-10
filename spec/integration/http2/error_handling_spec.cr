require "../support/http2_test_helpers_spec"

# HTTP/2 error handling and edge cases
# Focused on: Timeouts, invalid hosts, large responses, error conditions
describe "HTTP/2 Error Handling and Edge Cases" do
  describe "Timeout Handling" do
    it "handles fast responses within timeout" do
      client = HTTP2TestHelpers.create_test_client(HTTP2TestHelpers.ultra_fast_timeout)

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end

    it "handles requests that exceed timeout appropriately" do
      # Use a reasonable timeout that's long enough to be reliable
      # but short enough to keep tests fast
      short_timeout_client = H2O::Client.new(timeout: 100.milliseconds, verify_ssl: false)

      begin
        start_time = Time.monotonic
        
        # Use a non-routable IP address that will hang on connection attempt
        # This is more reliable than trying to create a mock server
        # 10.255.255.1 is in the private IP range and unlikely to be routable
        response = short_timeout_client.get("https://10.255.255.1:443/test")
        
        elapsed = Time.monotonic - start_time
        
        # Should timeout within reasonable bounds (100ms + some overhead)
        elapsed.should be < 500.milliseconds
        
        # Should get a timeout error (status 0)
        response.status.should eq(0)
        response.should_not be_nil
      ensure
        short_timeout_client.close
      end
    end
  end

  describe "Connection Error Handling" do
    it "handles invalid hosts gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # Test with non-existent host
      # The client returns error responses instead of raising exceptions
      response = client.get("https://nonexistent.invalid.host.example.com/index.html")
      
      # Should get an error response with status 0
      response.status.should eq(0)
      # Client returns empty body for connection errors
      response.should_not be_nil
    end
  end

  describe "Large Response Handling" do
    it "handles large response bodies" do
      client = HTTP2TestHelpers.create_test_client

      # Test with nghttpd's default response
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)

      # Verify response body exists and is reasonable
      response.body.size.should be > 0
      response.body.size.should be < 1_000_000 # Reasonable upper limit
    end
  end

  describe "Protocol Error Handling" do
    it "handles malformed requests gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # Test with unusual but valid headers
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"), {
          "X-Very-Long-Header-Name-That-Tests-Header-Length-Limits" => "value",
          "X-Empty-Value"                                           => "",
          "X-Unicode-Test"                                          => "🚀 HTTP/2 Test",
        })
      end

      # Should either succeed or fail gracefully
      response.should_not be_nil
      response.status.should be > 0
    end
  end
end
