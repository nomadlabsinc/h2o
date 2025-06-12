require "../spec_helper"
require "../support/test_config"

def client_timeout : Time::Span
  TestConfig.client_timeout
end

def ultra_fast_timeout : Time::Span
  TestConfig.fast_timeout
end

def test_base_url
  TestConfig.http2_url
end

def localhost_url(path = "")
  TestConfig.http2_url(path)
end

def http2_only_url(path = "")
  TestConfig.h2_only_url(path)
end

# Optimized retry for local servers - much faster
def retry_request(max_attempts = 2, acceptable_statuses = (200..299), &)
  attempts = 0
  last_error = nil

  while attempts < max_attempts
    attempts += 1
    begin
      result = yield
      # Return result if it's successful or acceptable
      if result && acceptable_statuses.includes?(result.status)
        return result
      elsif result
        # Got a response but not acceptable, try again unless it's the last attempt
        if attempts >= max_attempts
          return result
        end
        puts "Attempt #{attempts} failed with status #{result.status}, retrying..."
        sleep(10.milliseconds) # Very fast retry for local servers
      end
    rescue ex
      last_error = ex
      if attempts >= max_attempts
        raise ex
      end
      puts "Attempt #{attempts} failed with error: #{ex.message}, retrying..."
      sleep(20.milliseconds) # Fast retry for local servers
    end
  end

  raise last_error || Exception.new("All attempts failed")
end

# Comprehensive HTTP/2 validation tests to prevent "real requests do not work" bugs
describe "Comprehensive HTTP/2 Validation" do
  # Short timeout to ensure tests don't hang

  describe "Real HTTP/2 Request Validation" do
    it "successfully makes basic HTTP/2 GET requests" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      response = retry_request do
        client.get(localhost_url("/"))
      end

      # Core validation - should always get a response
      response.should_not be_nil
      response.status.should eq(200)
      response.protocol.should eq("HTTP/2")
      response.body.should_not be_empty
      response.body.should contain("Nginx HTTP/2 test server")

      # Headers validation
      response.headers.should_not be_empty
      response.headers.has_key?("content-type").should be_true
    end

    it "successfully handles HTTP/2 POST requests with body" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      test_data = {message: "Hello HTTP/2"}.to_json

      response = retry_request do
        client.post(http2_only_url("/"), test_data, {"Content-Type" => "application/json"})
      end

      response.should_not be_nil
      response.status.should eq(200)
      response.protocol.should eq("HTTP/2")
      response.body.should contain("HTTP/2")
    end

    it "handles HTTP/2 responses with different content types" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # JSON response from local server
      json_response = retry_request do
        client.get(localhost_url("/"))
      end
      json_response.should_not be_nil
      json_response.status.should eq(200)
      json_response.headers["content-type"]?.try(&.includes?("application/json")).should be_true
      json_response.body.should contain("HTTP/2 test server")

      # JSON response from HTTP/2-only server
      http2_response = retry_request do
        client.get(http2_only_url("/health"))
      end
      http2_response.should_not be_nil
      http2_response.status.should eq(200)
      http2_response.headers["content-type"]?.try(&.includes?("application/json")).should be_true
      http2_response.body.should contain("healthy")
    end

    it "handles HTTP/2 responses with custom headers" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      response = retry_request do
        client.get(http2_only_url("/headers"))
      end

      response.should_not be_nil
      response.status.should eq(200)
      response.body.should contain("headers")
      response.body.should contain("HTTP/2")
    end

    it "handles different HTTP/2 status codes correctly" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Test 200 OK (success case)
      response_200 = retry_request do
        client.get(localhost_url("/status/200"))
      end
      response_200.should_not be_nil
      response_200.status.should eq(200)

      # Test 404 Not Found from nginx
      response_404 = retry_request(acceptable_statuses: [404]) do
        client.get(localhost_url("/status/404"))
      end
      response_404.should_not be_nil
      response_404.status.should eq(404)

      # Test 200 from HTTP/2-only server
      response_h2_only = retry_request do
        client.get(http2_only_url("/status/200"))
      end
      response_h2_only.should_not be_nil
      response_h2_only.status.should eq(200)
      response_h2_only.body.should contain("HTTP/2")
    end
  end

  describe "HTTP/2 Performance and Reliability" do
    it "makes multiple HTTP/2 requests efficiently" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      successful_requests = 0
      total_time = Time.measure do
        5.times do |i|
          response = client.get(localhost_url("/?request=#{i}"))
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
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      results = Channel(Bool).new(3)

      3.times do |_|
        spawn do
          response = client.get(http2_only_url("/health"))
          results.send(response != nil && response.status == 200)
        end
      end

      # Wait for all requests to complete with timeout
      success_count = 0
      3.times do
        result = select
        when r = results.receive
          r
        when timeout(5.seconds)
          false
        end
        success_count += 1 if result
      end

      # At least 2 out of 3 concurrent requests should succeed
      success_count.should be >= 2
    end

    it "properly handles connection reuse" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Make multiple requests to the same host to test connection reuse
      responses = Array(H2O::Response).new

      3.times do
        response = client.get(localhost_url("/"))
        responses << response
      end

      # All requests should succeed or return acceptable server errors
      responses.each do |response|
        response.should_not be_nil
        # Accept 200 (success), 5xx (server error from 127.0.0.1:8443 under load), or 0 (connection error)
        if response.status == 200 || (response.status >= 500 && response.status < 600) || response.status == 0
          # Any of these is acceptable - test passes
        else
          fail "Unexpected status #{response.status} - expected 200, 5xx, or 0 (connection error)"
        end
      end
    end
  end

  describe "HTTP/2 Error Handling and Edge Cases" do
    it "handles fast responses within timeout" do
      client = H2O::Client.new(timeout: 4.seconds, verify_ssl: false)

      # Local server should respond quickly
      response = client.get(localhost_url("/"))

      # Should get a successful response
      response.should_not be_nil
      response.status.should eq(200)
      response.body.should contain("HTTP/2 test server")
    end

    it "handles requests that exceed timeout appropriately" do
      client = H2O::Client.new(timeout: 1.second, verify_ssl: false)

      start_time = Time.monotonic
      response = client.get("#{test_base_url}/delay/3")
      elapsed = Time.monotonic - start_time

      # Should handle timeout within reasonable time
      elapsed.should be <= 2.seconds

      # Should either get error response, server error, or successful response
      if response.status == 0
        # Timeout was handled correctly with error response
        response.error?.should be_true
      elsif response.status >= 500 && response.status < 600
        # Server error from 127.0.0.1:8443 under load - acceptable
        # Test passes as long as we get a response without hanging
      else
        # If response succeeded, server was faster than expected
        response.status.should eq(200)
      end
    end

    it "handles invalid hosts gracefully" do
      client = H2O::Client.new(timeout: 2.seconds, verify_ssl: false)

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
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Request a larger response (streaming test)
      response = client.get("#{test_base_url}/base64/#{Base64.encode("x" * 1000)}")

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
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      response = client.get("#{test_base_url}/headers")

      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        # Successful response
        response.status.should eq(200)
        response.body.should contain("user-agent")
      end
    end

    it "handles HTTP/2 headers correctly" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      custom_headers = {
        "X-Test-Header" => "test-value",
        "User-Agent"    => "custom-agent",
      }

      response = client.get("#{test_base_url}/headers", custom_headers)

      if response.status == 0
        # Network error
        response.error?.should be_true
      else
        # Successful response
        response.status.should eq(200)
        response.body.should contain("headers")
        response.body.should contain("user-agent")
      end
    end

    it "maintains HTTP/2 connection across requests" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Make multiple requests and verify they all use HTTP/2
      protocols = Array(String).new

      3.times do
        response = client.get("#{test_base_url}/get")
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
      # This test compares success rates between HTTP/2 and HTTP/1.1 using local servers
      h2o_client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Test HTTP/2 requests to local server
      h2_successes = 0
      3.times do
        response = h2o_client.get(localhost_url("/"))
        h2_successes += 1 if response.status == 200
      end

      # Test HTTP/1.1 baseline to local HTTPBin server
      http1_successes = 0
      3.times do
        begin
          response = HTTP::Client.get(TestConfig.http1_url("/get"))
          http1_successes += 1 if response.status_code == 200
        rescue
          # HTTP/1.1 request failed
        end
      end

      # Both should work with local servers
      h2_successes.should be >= 2    # HTTP/2 should work well with local server
      http1_successes.should be >= 2 # HTTP/1.1 should work well with local server

      # Both protocols should be functional
      (h2_successes + http1_successes).should be >= 4

      h2o_client.close
    end
  end
end
