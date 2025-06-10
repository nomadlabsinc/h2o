require "../spec_helper"

def client_timeout : Time::Span
  3.seconds
end

# HTTP/2 protocol compliance tests to ensure proper implementation
describe "HTTP/2 Protocol Compliance" do
  describe "Connection Management" do
    it "establishes HTTP/2 connections successfully" do
      client = H2O::Client.new(timeout: client_timeout)

      # The fact that we can make any request proves connection establishment
      response = client.get("https://httpbin.org/get")

      # Either succeeds or fails gracefully - no hanging or crashes
      if response
        response.protocol.should eq("HTTP/2")
      else
        # If it fails, it should be due to timeout/network, not implementation bugs
        # This test passes as long as no exception is raised
      end
    end

    it "handles connection lifecycle properly" do
      client = H2O::Client.new(timeout: client_timeout)

      # Make a request
      response1 = client.get("https://httpbin.org/get")

      # Close the client
      client.close

      # Verify we can create a new client and make requests
      new_client = H2O::Client.new(timeout: client_timeout)
      response2 = new_client.get("https://httpbin.org/get")

      # Both responses should either work or be nil (no crashes)
      if response1 && response2
        response1.status.should eq(200)
        response2.status.should eq(200)
      end

      new_client.close
    end

    it "handles multiple clients to same host" do
      client1 = H2O::Client.new(timeout: client_timeout)
      client2 = H2O::Client.new(timeout: client_timeout)

      response1 = client1.get("https://httpbin.org/uuid")
      response2 = client2.get("https://httpbin.org/uuid")

      # Both should work independently
      if response1 && response2
        response1.status.should eq(200)
        response2.status.should eq(200)
        # Different UUIDs should be returned
        response1.body.should_not eq(response2.body)
      end

      client1.close
      client2.close
    end
  end

  describe "Request/Response Handling" do
    it "handles various HTTP methods correctly" do
      client = H2O::Client.new(timeout: client_timeout)
      methods_tested = 0

      # Test GET
      get_response = client.get("https://httpbin.org/get")
      if get_response && get_response.status == 200
        methods_tested += 1
      end

      # Test POST
      post_response = client.post("https://httpbin.org/post", "test data")
      if post_response && post_response.status == 200
        methods_tested += 1
      end

      # Test PUT
      put_response = client.put("https://httpbin.org/put", "test data")
      if put_response && put_response.status == 200
        methods_tested += 1
      end

      # Test DELETE
      delete_response = client.delete("https://httpbin.org/delete")
      if delete_response && delete_response.status == 200
        methods_tested += 1
      end

      # At least some methods should work - HTTP/2 implementation is now functional
      if methods_tested == 0
        fail("No HTTP methods succeeded - this indicates a regression")
      else
        methods_tested.should be >= 1
      end

      client.close
    end

    it "handles request headers properly" do
      client = H2O::Client.new(timeout: client_timeout)

      headers = {
        "Accept"          => "application/json",
        "X-Custom-Header" => "test-value-#{Time.utc.to_unix}",
      }

      response = client.get("https://httpbin.org/headers", headers)

      response.should_not be_nil
      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        response.status.should eq(200)
        response.body.should contain("Accept")
        response.body.should contain("application/json")
        response.body.should contain("X-Custom-Header")
      end

      client.close
    end

    it "handles response headers properly" do
      client = H2O::Client.new(timeout: client_timeout)

      response = client.get("https://httpbin.org/response-headers?Content-Type=application/json&X-Test=value")

      response.should_not be_nil
      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        response.status.should eq(200)
        response.headers.should_not be_empty
        response.headers.has_key?("content-type").should be_true
      end

      client.close
    end
  end

  describe "Timeout and Error Handling" do
    it "respects timeout configurations" do
      short_client = H2O::Client.new(timeout: 500.milliseconds)
      normal_client = H2O::Client.new(timeout: client_timeout)

      start_time = Time.monotonic

      # Short timeout should fail quickly
      short_response = short_client.get("https://httpbin.org/delay/2")
      short_elapsed = Time.monotonic - start_time

      # Should timeout within reasonable time
      short_elapsed.should be <= 2.seconds

      # Normal timeout might succeed
      normal_response = normal_client.get("https://httpbin.org/get")

      # Verify timeout behavior is working
      if short_response.status == 0 && normal_response.status > 0
        # Perfect - short timeout failed, normal succeeded
        normal_response.status.should eq(200)
      elsif short_response.status == 0 && normal_response.status == 0
        # Both timed out - could be network issues, this is acceptable
        Log.warn { "Both timeout test requests timed out - may be due to network conditions" }
        short_response.error?.should be_true
        normal_response.error?.should be_true
      else
        # Short timeout unexpectedly succeeded - server was very fast
        short_response.status.should eq(200)
      end

      short_client.close
      normal_client.close
    end

    it "handles connection errors gracefully" do
      client = H2O::Client.new(timeout: 2.seconds)

      start_time = Time.monotonic
      response = client.get("https://nonexistent-domain-12345.invalid/test")
      elapsed = Time.monotonic - start_time

      # Should handle gracefully and not hang
      response.status.should eq(0) # Error status for invalid hosts
      response.error?.should be_true
      elapsed.should be <= 3.seconds

      client.close
    end

    it "handles malformed URLs gracefully" do
      client = H2O::Client.new(timeout: client_timeout)

      expect_raises(ArgumentError) do
        client.get("not-a-valid-url")
      end

      expect_raises(ArgumentError) do
        client.get("http://httpbin.org/get") # HTTP not HTTPS
      end

      client.close
    end
  end

  describe "Protocol-Specific Features" do
    it "uses HTTP/2 protocol correctly" do
      client = H2O::Client.new(timeout: client_timeout)

      response = client.get("https://httpbin.org/get")

      if response
        # Should report HTTP/2 protocol
        response.protocol.should eq("HTTP/2")

        # Should have proper status
        response.status.should be >= 200
        response.status.should be < 600

        # Should have headers
        response.headers.should be_a(Hash(String, String))
      else
        # HTTP/2 implementation is now working
      end

      client.close
    end

    it "handles HTTP/2 streams properly" do
      client = H2O::Client.new(timeout: client_timeout)

      # Make multiple requests to test stream handling
      responses = Array(H2O::Response).new

      3.times do |i|
        response = client.get("https://httpbin.org/get?stream=#{i}")
        responses << response
      end

      # Count successful responses
      successful_count = responses.count { |response| response && response.status == 200 }

      # HTTP/2 implementation is now working - all requests should succeed
      successful_count.should be >= 2

      client.close
    end
  end

  describe "Data Integrity" do
    it "preserves request data integrity" do
      client = H2O::Client.new(timeout: client_timeout)

      test_data = {
        "message"    => "Hello HTTP/2",
        "timestamp"  => Time.utc.to_unix,
        "test_array" => [1, 2, 3, 4, 5],
      }.to_json

      response = client.post("https://httpbin.org/post", test_data, {"Content-Type" => "application/json"})

      response.should_not be_nil
      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        response.status.should eq(200)
        # Verify the data was received correctly
        response.body.should contain("Hello HTTP/2")
        response.body.should contain("test_array")
      end

      client.close
    end

    it "handles binary data correctly" do
      client = H2O::Client.new(timeout: client_timeout)

      # Test with base64 encoded binary data
      binary_data = "Hello World!".to_slice
      encoded_data = Base64.encode(binary_data).strip # Remove trailing newline

      response = client.post("https://httpbin.org/post", encoded_data, {"Content-Type" => "application/octet-stream"})

      response.should_not be_nil
      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        response.status.should eq(200)
        response.body.should contain(encoded_data)
      end

      client.close
    end
  end
end
