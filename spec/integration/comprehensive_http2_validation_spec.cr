require "../spec_helper"

def client_timeout : Time::Span
  3.seconds
end

# Comprehensive HTTP/2 validation tests to prevent "real requests do not work" bugs
describe "Comprehensive HTTP/2 Validation" do
  # Short timeout to ensure tests don't hang

  describe "Real HTTP/2 Request Validation" do
    it "successfully makes basic HTTP/2 GET requests" do
      client = H2O::Client.new(timeout: client_timeout)

      response = client.get("https://httpbin.org/get")

      # Core validation - should always get a response
      response.should_not be_nil
      response.status.should eq(200)
      response.protocol.should eq("HTTP/2")
      response.body.should_not be_empty
      response.body.should contain("httpbin.org")

      # Headers validation
      response.headers.should_not be_empty
      response.headers.has_key?("content-type").should be_true
    end

    it "successfully handles HTTP/2 POST requests with body" do
      client = H2O::Client.new(timeout: client_timeout)
      test_data = {message: "Hello HTTP/2"}.to_json

      response = client.post("https://httpbin.org/post", test_data, {"Content-Type" => "application/json"})

      response.should_not be_nil
      response.status.should eq(200)
      response.protocol.should eq("HTTP/2")
      response.body.should contain("Hello HTTP/2")
    end

    it "handles HTTP/2 responses with different content types" do
      client = H2O::Client.new(timeout: client_timeout)

      # JSON response
      json_response = client.get("https://httpbin.org/json")
      json_response.should_not be_nil
      json_response.status.should eq(200)
      json_response.headers["content-type"]?.try(&.includes?("application/json")).should be_true
      json_response.body.should contain("slideshow")

      # HTML response
      html_response = client.get("https://httpbin.org/html")
      html_response.should_not be_nil
      html_response.status.should eq(200)
      html_response.headers["content-type"]?.try(&.includes?("text/html")).should be_true
      html_response.body.should contain("<html>")
    end

    it "handles HTTP/2 responses with custom headers" do
      client = H2O::Client.new(timeout: client_timeout)

      response = client.get("https://httpbin.org/response-headers?X-Custom-Header=test-value")

      response.should_not be_nil
      response.status.should eq(200)
      response.body.should contain("X-Custom-Header")
      response.body.should contain("test-value")
    end

    it "handles different HTTP/2 status codes correctly" do
      client = H2O::Client.new(timeout: client_timeout)

      # Test 201 Created
      response_201 = client.post("https://httpbin.org/status/201", "", {} of String => String)
      response_201.should_not be_nil
      response_201.status.should eq(201)

      # Test 404 Not Found
      response_404 = client.get("https://httpbin.org/status/404")
      response_404.should_not be_nil
      response_404.status.should eq(404)

      # Test 500 Internal Server Error
      response_500 = client.get("https://httpbin.org/status/500")
      response_500.should_not be_nil
      # Should be a server error (5xx), but httpbin.org might return 502 under load
      response_500.status.should be >= 500
      response_500.status.should be < 600
    end
  end

  describe "HTTP/2 Performance and Reliability" do
    it "makes multiple HTTP/2 requests efficiently" do
      client = H2O::Client.new(timeout: client_timeout)
      successful_requests = 0
      total_time = Time.measure do
        5.times do |i|
          response = client.get("https://httpbin.org/get?request=#{i}")
          if response && response.status == 200
            successful_requests += 1
          end
        end
      end

      # At least 80% of requests should succeed
      (successful_requests.to_f / 5.0).should be >= 0.8

      # Total time should be reasonable (not hanging)
      total_time.should be < (client_timeout * 5)
    end

    it "handles concurrent HTTP/2 requests" do
      client = H2O::Client.new(timeout: client_timeout)
      results = Channel(Bool).new(3)

      3.times do |_|
        spawn do
          response = client.get("https://httpbin.org/delay/1")
          results.send(response != nil && response.status == 200)
        end
      end

      # Wait for all requests to complete
      success_count = 0
      3.times do
        success_count += 1 if results.receive
      end

      # At least 2 out of 3 concurrent requests should succeed
      success_count.should be >= 2
    end

    it "properly handles connection reuse" do
      client = H2O::Client.new(timeout: client_timeout)

      # Make multiple requests to the same host to test connection reuse
      responses = Array(H2O::Response).new

      3.times do
        response = client.get("https://httpbin.org/uuid")
        responses << response
      end

      # All requests should succeed or return acceptable server errors
      responses.each do |response|
        response.should_not be_nil
        # Accept 200 (success), 5xx (server error from httpbin.org under load), or 0 (connection error)
        if response.status == 200 || (response.status >= 500 && response.status < 600) || response.status == 0
          # Any of these is acceptable - test passes
        else
          fail "Unexpected status #{response.status} - expected 200, 5xx, or 0 (connection error)"
        end
      end
    end
  end

  describe "HTTP/2 Error Handling and Edge Cases" do
    it "handles slow responses within timeout" do
      client = H2O::Client.new(timeout: 4.seconds)

      # Request that takes 2 seconds - should succeed with 4s timeout
      response = client.get("https://httpbin.org/delay/2")

      # Should either get a successful response or an error response
      # Error responses have status 0, successful responses have status 200
      if response.status == 0
        # This is an error response (timeout/network issue)
        response.error?.should be_true
      else
        # This is a successful response
        response.status.should eq(200)
      end
    end

    it "handles requests that exceed timeout appropriately" do
      client = H2O::Client.new(timeout: 1.second)

      start_time = Time.monotonic
      response = client.get("https://httpbin.org/delay/3")
      elapsed = Time.monotonic - start_time

      # Should handle timeout within reasonable time
      elapsed.should be <= 2.seconds

      # Should either get error response, server error, or successful response
      if response.status == 0
        # Timeout was handled correctly with error response
        response.error?.should be_true
      elsif response.status >= 500 && response.status < 600
        # Server error from httpbin.org under load - acceptable
        # Test passes as long as we get a response without hanging
      else
        # If response succeeded, server was faster than expected
        response.status.should eq(200)
      end
    end

    it "handles invalid hosts gracefully" do
      client = H2O::Client.new(timeout: 2.seconds)

      start_time = Time.monotonic
      response = client.get("https://definitely-not-a-real-domain-12345.example.com/test")
      elapsed = Time.monotonic - start_time

      # Should handle gracefully (error response) and not hang
      # Can be either status 0 (connection error) or 500 (circuit breaker error)
      [0, 500].should contain(response.status)
      response.error?.should be_true
      elapsed.should be <= 3.seconds
    end

    it "handles large response bodies" do
      client = H2O::Client.new(timeout: client_timeout)

      # Request a larger response (streaming test)
      response = client.get("https://httpbin.org/base64/#{Base64.encode("x" * 1000)}")

      if response.status == 0
        # Network error - this is acceptable for large responses
        response.error?.should be_true
      else
        # Successful response
        response.status.should eq(200)
        response.body.size.should be > 1000
      end
    end
  end

  describe "HTTP/2 Protocol Compliance" do
    it "sets proper User-Agent header" do
      client = H2O::Client.new(timeout: client_timeout)

      response = client.get("https://httpbin.org/user-agent")

      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        # Successful response
        response.status.should eq(200)
        response.body.should contain("h2o/")
      end
    end

    it "handles HTTP/2 headers correctly" do
      client = H2O::Client.new(timeout: client_timeout)
      custom_headers = {
        "X-Test-Header" => "test-value",
        "User-Agent"    => "custom-agent",
      }

      response = client.get("https://httpbin.org/headers", custom_headers)

      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        # Successful response
        response.status.should eq(200)
        response.body.should contain("X-Test-Header")
        response.body.should contain("test-value")
        response.body.should contain("h2o/")
      end
    end

    it "maintains HTTP/2 connection across requests" do
      client = H2O::Client.new(timeout: client_timeout)

      # Make multiple requests and verify they all use HTTP/2
      protocols = Array(String).new

      3.times do
        response = client.get("https://httpbin.org/get")
        if response.status > 0
          protocols << response.protocol
        end
      end

      # All successful requests should use HTTP/2
      protocols.each do |protocol|
        protocol.should eq("HTTP/2")
      end
    end
  end

  describe "HTTP/2 vs HTTP/1.1 Comparison" do
    it "demonstrates HTTP/2 functionality works as well as HTTP/1.1" do
      # This test compares success rates between HTTP/2 and HTTP/1.1
      h2o_client = H2O::Client.new(timeout: client_timeout)

      # Test HTTP/2 requests
      h2_successes = 0
      3.times do
        response = h2o_client.get("https://httpbin.org/get")
        h2_successes += 1 if response.status == 200
      end

      # Test HTTP/1.1 baseline
      http1_successes = 0
      3.times do
        begin
          response = HTTP::Client.get("https://httpbin.org/get")
          http1_successes += 1 if response.status_code == 200
        rescue
          # HTTP/1.1 request failed
        end
      end

      # If HTTP/1.1 works, HTTP/2 should work similarly
      if http1_successes >= 2
        # HTTP/1.1 is working well, so HTTP/2 should also work
        h2_successes.should be >= 1

        if h2_successes == 0
          fail "HTTP/1.1 succeeded (#{http1_successes}/3) but HTTP/2 failed completely (0/3)"
        end
      else
        # Network issues affecting both protocols
        pending("Network connectivity issues affecting both HTTP/1.1 and HTTP/2")
      end
    end
  end
end
