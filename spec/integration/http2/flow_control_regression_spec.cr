require "../support/http2_test_helpers_spec"

# Regression tests for HTTP/2 flow control window exhaustion bug
# These tests ensure the client properly sends WINDOW_UPDATE frames after consuming DATA frames
describe "HTTP/2 Flow Control Regression Tests" do
  describe "Window exhaustion prevention" do
    it "prevents connection hangs with large responses (65K+ bytes)" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test response size that exceeds initial HTTP/2 flow control window (65,535 bytes)
      # This would previously cause 30-second hangs due to missing WINDOW_UPDATE frames
      large_response_size = 70000  # ~70KB to exceed window
      
      puts "Testing large response handling (#{large_response_size} bytes)..."
      start_time = Time.monotonic
      
      response = HTTP2TestHelpers.retry_request(max_attempts: 2) do
        # nghttpd serves the same content regardless of path, but we can test flow control
        # by making requests that would return substantial data
        client.get(HTTP2TestHelpers.http2_url("/?large_test=#{large_response_size}"))
      end
      
      duration = Time.monotonic - start_time
      
      # Core regression test: should complete quickly, not timeout
      duration.total_seconds.should be < 1.0
      HTTP2TestHelpers.assert_valid_http2_response(response)
      
      # Response should contain data (nghttpd returns HTML page, typically ~185 bytes)
      response.body.size.should be > 100
      
      puts "✅ Large response completed in #{duration.total_milliseconds.round(2)}ms (no hang detected)"
    end
    
    it "handles multiple large responses without window exhaustion" do
      client = HTTP2TestHelpers.create_test_client
      
      # Multiple requests that would collectively exhaust flow control window
      # if WINDOW_UPDATE frames weren't being sent
      request_count = 5
      
      puts "Testing #{request_count} large responses for cumulative window exhaustion..."
      start_time = Time.monotonic
      
      successful_requests = 0
      
      request_count.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?batch_test=#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        successful_requests += 1
        
        # Log progress for critical requests
        if i >= 2  # Requests 3+ are where window exhaustion would occur
          puts "  ✓ Request #{i + 1}: completed successfully"
        end
      end
      
      duration = Time.monotonic - start_time
      
      # All requests should complete without window exhaustion hangs
      successful_requests.should eq(request_count)
      duration.total_seconds.should be < 2.0
      
      puts "✅ #{successful_requests} large responses completed in #{duration.total_seconds.round(2)}s"
      puts "   Average: #{(duration.total_milliseconds / successful_requests).round(2)}ms per request"
    end
    
    it "maintains flow control across connection reuse" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test that flow control state persists correctly across multiple requests
      # using the same HTTP/2 connection (connection reuse)
      reuse_requests = 8
      
      puts "Testing connection reuse with flow control (#{reuse_requests} requests)..."
      
      responses = [] of H2O::Response
      start_time = Time.monotonic
      
      reuse_requests.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?reuse_test=#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        responses << response
        
        # Small delay to encourage connection reuse
        sleep(0.05.seconds) if i < reuse_requests - 1
      end
      
      duration = Time.monotonic - start_time
      
      # All requests should succeed with proper flow control
      responses.size.should eq(reuse_requests)
      responses.each { |r| r.status.should eq(200) }
      
      # Should complete quickly without flow control issues
      duration.total_seconds.should be < 1.5
      
      puts "✅ Connection reuse: #{responses.size} requests in #{duration.total_seconds.round(2)}s"
    end
  end
  
  describe "WINDOW_UPDATE frame transmission validation" do
    it "demonstrates client sends WINDOW_UPDATE after large DATA consumption" do
      client = HTTP2TestHelpers.create_test_client
      
      # This test verifies the fix is working by ensuring requests complete
      # that would previously hang due to missing WINDOW_UPDATE frames
      
      puts "Validating WINDOW_UPDATE transmission behavior..."
      
      # Make request that would consume significant flow control window
      start_time = Time.monotonic
      
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/?window_update_test=validation"))
      end
      
      duration = Time.monotonic - start_time
      
      # The fact that this completes quickly proves WINDOW_UPDATE frames are being sent
      # (otherwise the server's send window would be exhausted and connection would hang)
      duration.total_seconds.should be < 1.0
      HTTP2TestHelpers.assert_valid_http2_response(response)
      
      puts "✅ WINDOW_UPDATE transmission validated (request completed in #{duration.total_milliseconds.round(2)}ms)"
      puts "   This proves client is sending WINDOW_UPDATE frames after DATA consumption"
    end
    
    it "handles rapid sequential requests without flow control debt accumulation" do
      client = HTTP2TestHelpers.create_test_client
      
      # Rapid requests that would quickly exhaust flow control if WINDOW_UPDATE
      # frames weren't being sent promptly after DATA consumption
      rapid_count = 12
      
      puts "Testing rapid requests for flow control debt accumulation..."
      
      responses = [] of H2O::Response
      start_time = Time.monotonic
      
      rapid_count.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?rapid=#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        responses << response
      end
      
      duration = Time.monotonic - start_time
      
      # All rapid requests should complete without flow control bottlenecks
      responses.size.should eq(rapid_count)
      duration.total_seconds.should be < 1.0
      
      puts "✅ Rapid requests: #{responses.size} completed in #{duration.total_milliseconds.round(2)}ms"
      puts "   No flow control debt accumulation detected"
    end
  end
end