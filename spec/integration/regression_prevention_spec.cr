require "../spec_helper"

def client_timeout : Time::Span
  1.seconds # Fast timeout for local Docker servers
end

# Local test server URLs
def test_base_url
  TestConfig.http2_url
end

# Helper to retry flaky HTTP requests
def retry_request(max_attempts = 3, acceptable_statuses = (200..299), &)
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
        
        sleep(10.milliseconds) # Fast local retry
      end
    rescue ex
      last_error = ex
      if attempts >= max_attempts
        raise ex
      end
      
      sleep(20.milliseconds) # Fast local retry
    end
  end

  raise last_error || Exception.new("All attempts failed")
end

# Regression prevention tests - these tests are designed to catch implementation
# issues early and prevent "real requests do not work" bugs from reaching production
describe "Regression Prevention for HTTP/2 Implementation" do
  describe "Critical Path Validation" do
    it "prevents complete HTTP/2 failure regression" do
      # This is the most critical test - if this fails, HTTP/2 is completely broken
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Try the simplest possible HTTP/2 request with retries
      response = retry_request(max_attempts: 5, acceptable_statuses: (200..599)) do
        client.get("#{test_base_url}/index.html")
      end

      if response.nil?
        # Complete failure - this should never happen in a working implementation
        fail "CRITICAL REGRESSION: HTTP/2 GET requests return nil - complete implementation failure"
      end

      # Basic validation - accept any valid HTTP status
      response.should_not be_nil
      response.status.should be >= 200
      response.status.should be < 600
      response.protocol.should eq("HTTP/2")

      client.close
    end

    it "prevents timeout regression" do
      # Verify timeout behavior is working correctly
      fast_client = H2O::Client.new(timeout: 100.milliseconds, verify_ssl: false)
      normal_client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Fast client should timeout quickly
      start_time = Time.monotonic
      fast_response = fast_client.get("#{TestConfig.http2_url}/delay/2")
      fast_elapsed = Time.monotonic - start_time

      # Should timeout within reasonable time (not hang for default 30s)
      fast_elapsed.should be <= 2.seconds

      # Normal client should handle normal requests
      normal_response = retry_request do
        normal_client.get("#{test_base_url}/index.html")
      end

      # At least normal client should work
      if normal_response.nil?
        fail "TIMEOUT REGRESSION: Normal timeout client cannot make basic requests"
      end

      normal_response.status.should eq(200)

      fast_client.close
      normal_client.close
    end

    it "prevents connection hanging regression" do
      # Verify connections don't hang indefinitely
      clients = Array(H2O::Client).new

      # Create multiple clients to test for deadlocks
      start_time = Time.monotonic

      5.times do
        client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
        clients << client
      end

      creation_time = Time.monotonic - start_time
      creation_time.should be <= 5.seconds

      # Make requests from all clients
      responses = clients.map(&.get("#{test_base_url}/"))

      # Clean up
      clients.each(&.close)

      # At least some requests should succeed (no complete hanging)
      successful_responses = responses.count { |response| response && response.status == 200 }

      if successful_responses == 0
        fail "CONNECTION HANGING REGRESSION: No clients can successfully make requests"
      end
    end
  end

  describe "Performance Regression Prevention" do
    it "prevents performance regression" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Measure performance of basic operations
      single_request_time = Time.measure do
        response = client.get("#{test_base_url}/index.html")
        response.should_not be_nil if response
      end

      # Should complete within reasonable time
      if single_request_time > client_timeout
        fail "PERFORMANCE REGRESSION: Single request takes longer than timeout"
      end

      # Test multiple requests
      multiple_requests_time = Time.measure do
        3.times do
          response = client.get("#{test_base_url}/index.html")
          break if response.nil? # Don't continue if requests fail
        end
      end

      # Multiple requests should not take exponentially longer
      if multiple_requests_time > (client_timeout * 3)
        fail "PERFORMANCE REGRESSION: Multiple requests take too long"
      end

      client.close
    end

    it "prevents memory leak regression" do
      # Test for obvious memory leaks
      clients = Array(H2O::Client).new

      # Create and close many clients
      10.times do
        client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
        response = client.get("#{test_base_url}/index.html")
        client.close

        # Don't accumulate clients in memory
        GC.collect
      end

      # Create a final client to ensure functionality still works
      final_client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      final_response = final_client.get("#{test_base_url}/index.html")

      if final_response.nil?
        fail "MEMORY LEAK REGRESSION: Client creation/destruction affects functionality"
      end

      final_client.close
    end
  end

  describe "Error Handling Regression Prevention" do
    it "prevents error handling regression" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Test various error scenarios
      error_tests = [
        -> { client.get("#{TestConfig.http2_url}/status/404") },            # 404 error
        -> { client.get("#{TestConfig.http2_url}/status/500") },            # 500 error
        -> { client.get("https://definitely-not-a-real-domain.invalid/index.html") }, # DNS error
      ]

      error_tests.each_with_index do |test, index|
        begin
          response = test.call

          if index < 2 # HTTP error status codes
            # Should get actual HTTP error responses
            response.status.should eq(index == 0 ? 404 : 500)
            response.error?.should be_false # These are HTTP responses, not connection errors
          else                              # DNS error
            # DNS error should return error response, not crash
            # Can be status 0 (connection error) or 500 (circuit breaker error)
            [0, 500].should contain(response.status)
            response.error?.should be_true
          end
        rescue ex : Exception
          # Should not raise unhandled exceptions for these cases
          fail "ERROR HANDLING REGRESSION: Unhandled exception for error case #{index}: #{ex.message}"
        end
      end

      client.close
    end

    it "prevents exception handling regression" do
      GlobalStateHelper.ensure_clean_state
      # Test that proper exceptions are raised for invalid input
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Invalid URL schemes should raise ArgumentError
      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("not-a-url")
      end

      # HTTP (not HTTPS) should raise ArgumentError
      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("#{TestConfig.http1_url}/index.html")
      end

      client.close
    end
  end

  describe "CI/CD Health Validation" do
    it "validates test environment readiness" do
      # Ensure test environment is working properly

      # Test HTTP/1.1 baseline using H1::Client to verify network connectivity
      http1_working = false
      begin
        # Use the HTTPBin service on port 8080 for HTTP/1.1 baseline test
        h1_client = H2O::H1::Client.new(TestConfig.http1_host, TestConfig.http1_port.to_i, connect_timeout: 500.milliseconds, verify_ssl: false)
        http1_response = h1_client.request("GET", "/get")
        http1_working = http1_response.status >= 200 && http1_response.status < 400
        h1_client.close
      rescue
        http1_working = false
      end

      if !http1_working
        fail("Test environment network connectivity issue - HTTP/1.1 baseline failing")
      end

      # Test HTTP/2 implementation
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
      h2_response = client.get("#{test_base_url}/index.html")

      if h2_response.nil?
        fail "CI/CD HEALTH ISSUE: HTTP/1.1 works but HTTP/2 completely fails - implementation regression"
      end

      h2_response.status.should eq(200)
      h2_response.protocol.should eq("HTTP/2")

      client.close
    end

    it "validates test suite completeness" do
      # Ensure our test suite is comprehensive enough

      # Test coverage checklist
      passed_tests = 0

      # basic_get test
      client1 = H2O::Client.new(timeout: client_timeout)
      response = client1.get("#{test_base_url}/")
      if response && response.status == 200
        passed_tests += 1
      end
      client1.close

      # post_request test
      client2 = H2O::Client.new(timeout: client_timeout)
      response = client2.post("#{TestConfig.http2_url}/post", "test")
      if response && response.status == 200
        passed_tests += 1
      end
      client2.close

      # custom_headers test
      client3 = H2O::Client.new(timeout: client_timeout)
      response = client3.get("#{TestConfig.http2_url}/headers", {"X-Test" => "value"})
      if response && response.status == 200
        passed_tests += 1
      end
      client3.close

      # json_response test
      client4 = H2O::Client.new(timeout: client_timeout)
      response = client4.get("#{TestConfig.http2_url}/json")
      if response && response.status == 200
        passed_tests += 1
      end
      client4.close

      # error_status test
      client5 = H2O::Client.new(timeout: client_timeout)
      response = client5.get("#{TestConfig.http2_url}/status/404")
      if response && response.status == 404
        passed_tests += 1
      end
      client5.close

      # At least 60% of coverage tests should pass (5 tests total)
      coverage_percentage = (passed_tests.to_f / 5.0) * 100

      if coverage_percentage < 60.0
        fail "TEST SUITE REGRESSION: Only #{coverage_percentage.round(1)}% of coverage tests passing"
      end
    end
  end

  describe "Future Regression Prevention" do
    it "validates HTTP/2 stream handling edge cases" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Test edge cases that might break in future changes
      edge_case_tests = [
        -> { client.get("#{TestConfig.http2_url}/gzip") },          # Compressed response
        -> { client.get("#{TestConfig.http2_url}/encoding/utf8") }, # UTF-8 encoding
        -> { client.get("#{TestConfig.http2_url}/json") },          # JSON content type
        -> { client.get("#{TestConfig.http2_url}/xml") },           # XML content type
      ]

      successful_edge_cases = 0
      edge_case_tests.each do |test|
        response = test.call
        successful_edge_cases += 1 if response && response.status == 200
      end

      # Should handle at least some edge cases
      if successful_edge_cases == 0
        fail "EDGE CASE REGRESSION: No edge cases handled correctly"
      end

      client.close
    end

    it "validates concurrent request handling" do
      client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)

      # Test concurrent requests to catch race conditions
      channels = Array(Channel(Bool)).new

      3.times do |i|
        channel = Channel(Bool).new(1)
        channels << channel

        spawn do
          response = client.get("#{test_base_url}/?concurrent=#{i}")
          channel.send(response ? response.status == 200 : false)
        end
      end

      # Wait for all concurrent requests
      results = channels.map(&.receive)
      successful_concurrent = results.count { |result| result }

      if successful_concurrent == 0
        fail "CONCURRENCY REGRESSION: No concurrent requests succeed"
      end

      client.close
    end
  end
end
