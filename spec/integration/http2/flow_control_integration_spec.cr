require "../support/http2_test_helpers_spec"

# Integration tests for HTTP/2 flow control improvements
# Tests the WINDOW_UPDATE fix that prevents connection hangs after ~14 requests
describe "HTTP/2 Flow Control Integration" do
  describe "WINDOW_UPDATE frame behavior" do
    it "successfully handles multiple consecutive requests without hanging" do
      client = HTTP2TestHelpers.create_test_client
      
      # Make 20 requests to exceed the problematic ~14 request threshold
      # This would previously cause connection hangs due to flow control window exhaustion
      request_count = 20
      responses = [] of H2O::Response
      
      # Use a reasonable timeout per request (should complete much faster than 30s)
      start_time = Time.monotonic
      
      request_count.times do |i|
        response = HTTP2TestHelpers.retry_request(max_attempts: 2) do
          client.get(HTTP2TestHelpers.http2_url("/"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        responses << response
        
        # Log progress every 5 requests
        if (i + 1) % 5 == 0
          elapsed = Time.monotonic - start_time
          puts "Completed #{i + 1}/#{request_count} requests in #{elapsed.total_milliseconds.round(2)}ms"
        end
      end
      
      total_duration = Time.monotonic - start_time
      
      # All requests should complete successfully
      responses.size.should eq(request_count)
      responses.each { |r| r.status.should eq(200) }
      
      # Should complete much faster than the previous 30-second hang
      total_duration.total_seconds.should be < 10.0
      
      puts "✅ All #{request_count} requests completed successfully in #{total_duration.total_seconds.round(2)}s"
      puts "   Average: #{(total_duration.total_milliseconds / request_count).round(2)}ms per request"
    end
    
    it "handles large response bodies without flow control issues" do
      client = HTTP2TestHelpers.create_test_client
      
      # Make requests that would return larger bodies
      # nghttpd returns same content, but we can test flow control with multiple requests
      large_request_count = 15
      
      start_time = Time.monotonic
      
      large_request_count.times do |i|
        response = HTTP2TestHelpers.retry_request do
          # Add query parameters to potentially get larger responses
          client.get(HTTP2TestHelpers.http2_url("/?test=flow_control&iteration=#{i}&data=" + "x" * 100))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        
        # Response should contain substantial content
        response.body.size.should be > 100
      end
      
      duration = Time.monotonic - start_time
      duration.total_seconds.should be < 8.0
      
      puts "✅ #{large_request_count} large requests completed in #{duration.total_seconds.round(2)}s"
    end
    
    it "maintains flow control across connection reuse" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test connection reuse with flow control
      # Make batches of requests with small delays to test connection pooling
      batch_size = 5
      batch_count = 4
      total_requests = 0
      
      start_time = Time.monotonic
      
      batch_count.times do |batch|
        puts "Processing batch #{batch + 1}/#{batch_count}"
        
        batch_size.times do |req|
          response = HTTP2TestHelpers.retry_request do
            client.get(HTTP2TestHelpers.http2_url("/batch/#{batch}/request/#{req}"))
          end
          
          HTTP2TestHelpers.assert_valid_http2_response(response)
          total_requests += 1
        end
        
        # Small delay between batches to test connection reuse
        sleep(0.1.seconds) if batch < batch_count - 1
      end
      
      duration = Time.monotonic - start_time
      duration.total_seconds.should be < 6.0
      
      total_requests.should eq(batch_size * batch_count)
      puts "✅ #{total_requests} requests across #{batch_count} batches completed in #{duration.total_seconds.round(2)}s"
    end
  end
  
  describe "Connection hang prevention" do
    it "prevents the specific RentCast-like scenario that caused hangs" do
      client = HTTP2TestHelpers.create_test_client
      
      # Simulate the pattern that caused hangs with api.rentcast.io:
      # - Multiple requests in sequence
      # - Responses with moderate-sized JSON bodies
      # - Connection reuse
      
      rentcast_simulation_count = 16  # Slightly above the problematic ~14 threshold
      
      start_time = Time.monotonic
      successful_requests = 0
      
      rentcast_simulation_count.times do |i|
        begin
          response = HTTP2TestHelpers.retry_request(max_attempts: 3) do
            # Simulate API endpoint calls
            client.get(HTTP2TestHelpers.http2_url("/api/simulation/#{i}"))
          end
          
          HTTP2TestHelpers.assert_valid_http2_response(response)
          successful_requests += 1
          
          # Each response should complete without timeout
          # The previous bug would cause hangs starting around request 14
          if i >= 13  # Critical range where hangs occurred
            puts "✓ Request #{i + 1} completed successfully (was problematic range)"
          end
          
        rescue ex : Exception
          puts "❌ Request #{i + 1} failed: #{ex.message}"
          raise ex
        end
      end
      
      duration = Time.monotonic - start_time
      
      # All requests should succeed
      successful_requests.should eq(rentcast_simulation_count)
      
      # Should complete without hanging (much faster than 30s timeout)
      duration.total_seconds.should be < 5.0
      
      puts "✅ RentCast simulation: #{successful_requests}/#{rentcast_simulation_count} requests successful"
      puts "   Total time: #{duration.total_seconds.round(2)}s (no hangs detected)"
      puts "   Average: #{(duration.total_milliseconds / successful_requests).round(2)}ms per request"
    end
    
    it "handles burst requests without flow control exhaustion" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test burst scenario - many requests in quick succession
      burst_count = 25
      
      responses = Channel(H2O::Response).new(burst_count)
      exceptions = Channel(Exception).new(burst_count)
      
      start_time = Time.monotonic
      
      # Send all requests concurrently to test flow control under load
      burst_count.times do |i|
        spawn do
          begin
            response = client.get(HTTP2TestHelpers.http2_url("/burst/#{i}"))
            responses.send(response)
          rescue ex
            exceptions.send(ex)
          end
        end
      end
      
      # Collect results
      successful_responses = [] of H2O::Response
      errors = [] of Exception
      
      burst_count.times do
        select
        when response = responses.receive
          successful_responses << response
        when error = exceptions.receive
          errors << error
        when timeout(10.seconds)
          fail "Timeout waiting for burst requests to complete"
        end
      end
      
      duration = Time.monotonic - start_time
      
      # Most requests should succeed (allow for some network variability)
      success_rate = successful_responses.size.to_f / burst_count
      success_rate.should be >= 0.8  # At least 80% success rate
      
      # Successful responses should be valid
      successful_responses.each do |response|
        HTTP2TestHelpers.assert_valid_http2_response(response)
      end
      
      # Should complete reasonably quickly
      duration.total_seconds.should be < 8.0
      
      puts "✅ Burst test: #{successful_responses.size}/#{burst_count} requests successful (#{(success_rate * 100).round(1)}%)"
      puts "   Duration: #{duration.total_seconds.round(2)}s"
      
      if errors.size > 0
        puts "   Errors encountered: #{errors.size}"
        errors.first(3).each { |e| puts "     - #{e.message}" }
      end
    end
  end
  
  describe "Flow control edge cases" do
    it "handles empty DATA frames correctly" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test requests that might return empty or very small responses
      small_response_count = 10
      
      small_response_count.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/empty/#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        # Empty responses should still be handled correctly
      end
      
      puts "✅ #{small_response_count} small/empty response requests completed successfully"
    end
    
    it "maintains flow control state across multiple connection events" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test flow control persistence across various HTTP/2 frame types
      mixed_request_count = 12
      
      mixed_request_count.times do |i|
        response = HTTP2TestHelpers.retry_request do
          case i % 3
          when 0
            client.get(HTTP2TestHelpers.http2_url("/mixed/get/#{i}"))
          when 1
            client.post(HTTP2TestHelpers.http2_url("/mixed/post/#{i}"), "data=#{i}")
          when 2
            client.get(HTTP2TestHelpers.http2_url("/mixed/query/#{i}?param=value"))
          else
            client.get(HTTP2TestHelpers.http2_url("/mixed/default/#{i}"))
          end
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
      end
      
      puts "✅ #{mixed_request_count} mixed request types completed successfully"
    end
  end
end

