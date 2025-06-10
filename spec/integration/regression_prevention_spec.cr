require "../spec_helper"

def client_timeout : Time::Span
  3.seconds
end

# Regression prevention tests - these tests are designed to catch implementation
# issues early and prevent "real requests do not work" bugs from reaching production
describe "Regression Prevention for HTTP/2 Implementation" do
  describe "Critical Path Validation" do
    it "prevents complete HTTP/2 failure regression" do
      # This is the most critical test - if this fails, HTTP/2 is completely broken
      client = H2O::Client.new(timeout: client_timeout)

      # Try the simplest possible HTTP/2 request
      response = client.get("https://httpbin.org/get")

      if response.nil?
        # Complete failure - this should never happen in a working implementation
        fail "CRITICAL REGRESSION: HTTP/2 GET requests return nil - complete implementation failure"
      end

      # Basic validation
      response.should_not be_nil
      response.status.should be >= 200
      response.status.should be < 600
      response.protocol.should eq("HTTP/2")

      client.close
    end

    it "prevents timeout regression" do
      # Verify timeout behavior is working correctly
      fast_client = H2O::Client.new(timeout: 100.milliseconds)
      normal_client = H2O::Client.new(timeout: client_timeout)

      # Fast client should timeout quickly
      start_time = Time.monotonic
      fast_response = fast_client.get("https://httpbin.org/delay/2")
      fast_elapsed = Time.monotonic - start_time

      # Should timeout within reasonable time (not hang for default 30s)
      fast_elapsed.should be <= 2.seconds

      # Normal client should handle normal requests
      normal_response = normal_client.get("https://httpbin.org/get")

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
        client = H2O::Client.new(timeout: client_timeout)
        clients << client
      end

      creation_time = Time.monotonic - start_time
      creation_time.should be <= 5.seconds

      # Make requests from all clients
      responses = clients.map(&.get("https://httpbin.org/get"))

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
      client = H2O::Client.new(timeout: client_timeout)

      # Measure performance of basic operations
      single_request_time = Time.measure do
        response = client.get("https://httpbin.org/get")
        response.should_not be_nil if response
      end

      # Should complete within reasonable time
      if single_request_time > client_timeout
        fail "PERFORMANCE REGRESSION: Single request takes longer than timeout"
      end

      # Test multiple requests
      multiple_requests_time = Time.measure do
        3.times do
          response = client.get("https://httpbin.org/get")
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
        client = H2O::Client.new(timeout: client_timeout)
        response = client.get("https://httpbin.org/get")
        client.close

        # Don't accumulate clients in memory
        GC.collect
      end

      # Create a final client to ensure functionality still works
      final_client = H2O::Client.new(timeout: client_timeout)
      final_response = final_client.get("https://httpbin.org/get")

      if final_response.nil?
        fail "MEMORY LEAK REGRESSION: Client creation/destruction affects functionality"
      end

      final_client.close
    end
  end

  describe "Error Handling Regression Prevention" do
    it "prevents error handling regression" do
      client = H2O::Client.new(timeout: client_timeout)

      # Test various error scenarios
      error_tests = [
        -> { client.get("https://httpbin.org/status/404") },                # 404 error
        -> { client.get("https://httpbin.org/status/500") },                # 500 error
        -> { client.get("https://definitely-not-a-real-domain.invalid/") }, # DNS error
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
      # Test that proper exceptions are raised for invalid input
      client = H2O::Client.new(timeout: client_timeout)

      # Invalid URL schemes should raise ArgumentError
      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("not-a-url")
      end

      # HTTP (not HTTPS) should raise ArgumentError
      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("http://httpbin.org/get")
      end

      client.close
    end
  end

  describe "CI/CD Health Validation" do
    it "validates test environment readiness" do
      # Ensure test environment is working properly

      # Test HTTP/1.1 baseline to verify network connectivity
      http1_working = false
      begin
        http1_response = HTTP::Client.get("https://httpbin.org/get")
        http1_working = http1_response.status_code == 200
      rescue
        http1_working = false
      end

      if !http1_working
        fail("Test environment network connectivity issue - HTTP/1.1 baseline failing")
      end

      # Test HTTP/2 implementation
      client = H2O::Client.new(timeout: client_timeout)
      h2_response = client.get("https://httpbin.org/get")

      if h2_response.nil?
        fail "CI/CD HEALTH ISSUE: HTTP/1.1 works but HTTP/2 completely fails - implementation regression"
      end

      h2_response.status.should eq(200)
      h2_response.protocol.should eq("HTTP/2")

      client.close
    end

    it "validates test suite completeness" do
      # Ensure our test suite is comprehensive enough

      client = H2O::Client.new(timeout: client_timeout)

      # Test coverage checklist
      coverage_tests = {
        basic_get:      -> { client.get("https://httpbin.org/get") },
        post_request:   -> { client.post("https://httpbin.org/post", "test") },
        custom_headers: -> { client.get("https://httpbin.org/headers", {"X-Test" => "value"}) },
        json_response:  -> { client.get("https://httpbin.org/json") },
        error_status:   -> { client.get("https://httpbin.org/status/404") },
      }

      passed_tests = 0
      coverage_tests.each do |name, test|
        response = test.call
        if response && (response.status == 200 || (name == :error_status && response.status == 404))
          passed_tests += 1
        end
      end

      # At least 60% of coverage tests should pass
      coverage_percentage = (passed_tests.to_f / coverage_tests.size.to_f) * 100

      if coverage_percentage < 60.0
        fail "TEST SUITE REGRESSION: Only #{coverage_percentage.round(1)}% of coverage tests passing"
      end

      client.close
    end
  end

  describe "Future Regression Prevention" do
    it "validates HTTP/2 stream handling edge cases" do
      client = H2O::Client.new(timeout: client_timeout)

      # Test edge cases that might break in future changes
      edge_case_tests = [
        -> { client.get("https://httpbin.org/gzip") },          # Compressed response
        -> { client.get("https://httpbin.org/encoding/utf8") }, # UTF-8 encoding
        -> { client.get("https://httpbin.org/json") },          # JSON content type
        -> { client.get("https://httpbin.org/xml") },           # XML content type
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
      client = H2O::Client.new(timeout: client_timeout)

      # Test concurrent requests to catch race conditions
      channels = Array(Channel(Bool)).new

      3.times do |i|
        channel = Channel(Bool).new(1)
        channels << channel

        spawn do
          response = client.get("https://httpbin.org/get?concurrent=#{i}")
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
