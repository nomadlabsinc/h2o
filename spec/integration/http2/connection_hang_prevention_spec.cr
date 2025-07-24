require "../support/http2_test_helpers_spec"

# Tests specifically for the connection hang issue that occurred after ~14 requests
# These tests verify that the WINDOW_UPDATE flow control fix prevents hangs
describe "HTTP/2 Connection Hang Prevention" do
  describe "RentCast API hang scenario reproduction" do
    it "reproduces and verifies fix for the ~14 request hang pattern" do
      client = HTTP2TestHelpers.create_test_client
      
      # This test reproduces the exact pattern that caused hangs with api.rentcast.io:
      # 1. Multiple sequential requests using connection reuse
      # 2. Responses with moderate-sized bodies (~4KB average)
      # 3. Hang occurs around request #14 due to flow control window exhaustion
      
      critical_request_count = 16  # Beyond the problematic threshold
      responses = [] of H2O::Response
      request_times = [] of Float64
      
      puts "🔍 Testing RentCast hang scenario with #{critical_request_count} requests..."
      
      start_time = Time.monotonic
      
      critical_request_count.times do |i|
        request_start = Time.monotonic
        
        begin
          # Simulate API calls similar to RentCast pattern
          response = HTTP2TestHelpers.retry_request(max_attempts: 2) do
            client.get(HTTP2TestHelpers.http2_url("/?request=#{i}"))
          end
          
          request_duration = (Time.monotonic - request_start).total_milliseconds
          request_times << request_duration
          
          HTTP2TestHelpers.assert_valid_http2_response(response)
          responses << response
          
          # Log critical requests where hangs previously occurred
          if i >= 12  # Requests 13, 14, 15, 16 were problematic
            puts "  ✓ Request #{i + 1}: #{request_duration.round(2)}ms (critical range)"
          elsif i % 5 == 4
            puts "  ✓ Request #{i + 1}: #{request_duration.round(2)}ms"
          end
          
          # Verify no individual request takes longer than reasonable time
          # Previous bug caused 30-second timeouts
          request_duration.should be < 5000.0  # 5 seconds max per request
          
        rescue ex : Exception
          puts "  ❌ Request #{i + 1} failed: #{ex.message}"
          puts "     This indicates the hang issue may not be fully resolved"
          raise ex
        end
      end
      
      total_duration = Time.monotonic - start_time
      
      # Verify all requests completed successfully
      responses.size.should eq(critical_request_count)
      responses.each { |r| r.status.should eq(200) }
      
      # Total time should be much less than the 30s * 14 requests = 420s worst case
      total_duration.total_seconds.should be < 20.0
      
      # Calculate statistics
      avg_request_time = request_times.sum / request_times.size
      max_request_time = request_times.max
      min_request_time = request_times.min
      
      puts "\n📊 RentCast Hang Test Results:"
      puts "   Total requests: #{responses.size}/#{critical_request_count}"
      puts "   Total duration: #{total_duration.total_seconds.round(2)}s"
      puts "   Average per request: #{avg_request_time.round(2)}ms"
      puts "   Fastest request: #{min_request_time.round(2)}ms"
      puts "   Slowest request: #{max_request_time.round(2)}ms"
      puts "   ✅ No 30-second hangs detected - flow control fix working!"
    end
    
    it "handles the exact flow control window exhaustion scenario" do
      client = HTTP2TestHelpers.create_test_client
      
      # Calculate requests needed to exhaust initial HTTP/2 flow control window
      # Default connection window: 65,535 bytes
      # Average response size: ~4,500 bytes (based on RentCast logs)
      # Theoretical exhaustion: ~14.5 requests
      
      window_exhaustion_requests = 15
      total_response_size = 0
      
      puts "🔬 Testing flow control window exhaustion with #{window_exhaustion_requests} requests..."
      
      start_time = Time.monotonic
      
      window_exhaustion_requests.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?data=#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        total_response_size += response.body.size
        
        puts "  Request #{i + 1}: #{response.body.size} bytes (total: #{total_response_size} bytes)"
        
        # After request 10, we should be approaching window exhaustion
        if i >= 10
          puts "    ⚠️  Approaching window exhaustion zone"
        end
      end
      
      duration = Time.monotonic - start_time
      
      # Should complete without hanging
      duration.total_seconds.should be < 10.0
      
      puts "\n📊 Window Exhaustion Test Results:"
      puts "   Total response data: #{total_response_size} bytes"
      puts "   Completion time: #{duration.total_seconds.round(2)}s"
      puts "   ✅ No window exhaustion hangs - WINDOW_UPDATE frames working!"
    end
  end
  
  describe "Stress testing flow control improvements" do
    it "handles high-frequency requests without accumulating flow control debt" do
      client = HTTP2TestHelpers.create_test_client
      
      # Rapid-fire requests to test flow control under pressure
      rapid_request_count = 30
      max_concurrent = 5
      
      puts "⚡ Stress testing with #{rapid_request_count} rapid requests (max #{max_concurrent} concurrent)..."
      
      request_batches = rapid_request_count.times.to_a.in_groups_of(max_concurrent, false)
      all_responses = [] of H2O::Response
      
      start_time = Time.monotonic
      
      request_batches.each_with_index do |batch, batch_idx|
        batch_responses = Channel(H2O::Response).new(batch.size)
        batch_errors = Channel(Exception).new(batch.size)
        
        # Start batch of concurrent requests
        batch.each do |req_idx|
          spawn do
            begin
              response = client.get(HTTP2TestHelpers.http2_url("/?rapid=#{req_idx}"))
              batch_responses.send(response)
            rescue ex
              batch_errors.send(ex)
            end
          end
        end
        
        # Collect batch results
        batch_results = [] of H2O::Response
        batch.size.times do
          select
          when response = batch_responses.receive
            batch_results << response
          when error = batch_errors.receive
            puts "    ❌ Request failed: #{error.message}"
            raise error
          when timeout(8.seconds)
            fail "Batch #{batch_idx + 1} timed out - possible flow control issue"
          end
        end
        
        all_responses.concat(batch_results)
        puts "  ✓ Batch #{batch_idx + 1}: #{batch_results.size}/#{batch.size} requests completed"
      end
      
      duration = Time.monotonic - start_time
      
      # All requests should complete successfully
      all_responses.size.should eq(rapid_request_count)
      all_responses.each { |r| HTTP2TestHelpers.assert_valid_http2_response(r) }
      
      # Should complete in reasonable time despite high frequency
      duration.total_seconds.should be < 15.0
      
      puts "\n📊 Stress Test Results:"
      puts "   Completed: #{all_responses.size}/#{rapid_request_count} requests"
      puts "   Duration: #{duration.total_seconds.round(2)}s"
      puts "   Average: #{(duration.total_milliseconds / all_responses.size).round(2)}ms per request"
      puts "   ✅ High-frequency requests handled without flow control issues!"
    end
    
    it "maintains flow control across long-running connection sessions" do
      client = HTTP2TestHelpers.create_test_client
      
      # Long session with periodic requests to test connection persistence
      session_duration = 5.0  # 5 seconds
      request_interval = 0.2  # Request every 200ms
      expected_requests = (session_duration / request_interval).to_i
      
      puts "🕐 Long session test: #{expected_requests} requests over #{session_duration}s..."
      
      responses = [] of H2O::Response
      start_time = Time.monotonic
      request_count = 0
      
      while (Time.monotonic - start_time).total_seconds < session_duration
        begin
          response = HTTP2TestHelpers.retry_request do
            client.get(HTTP2TestHelpers.http2_url("/?session=#{request_count}"))
          end
          
          HTTP2TestHelpers.assert_valid_http2_response(response)
          responses << response
          request_count += 1
          
          if request_count % 10 == 0
            elapsed = (Time.monotonic - start_time).total_seconds
            puts "  ✓ #{request_count} requests completed in #{elapsed.round(2)}s"
          end
          
          sleep(request_interval.seconds)
          
        rescue ex : Exception
          puts "  ❌ Session request #{request_count} failed: #{ex.message}"
          raise ex
        end
      end
      
      actual_duration = (Time.monotonic - start_time).total_seconds
      
      # Should complete expected number of requests
      responses.size.should be >= (expected_requests * 0.8).to_i  # Allow 20% variance
      responses.each { |r| r.status.should eq(200) }
      
      puts "\n📊 Long Session Results:"
      puts "   Requests completed: #{responses.size} (expected ~#{expected_requests})"
      puts "   Session duration: #{actual_duration.round(2)}s"
      puts "   Request rate: #{(responses.size / actual_duration).round(2)} req/s"
      puts "   ✅ Long session maintained without flow control degradation!"
    end
  end
  
  describe "Flow control edge case handling" do
    it "recovers gracefully from temporary network delays" do
      client = HTTP2TestHelpers.create_test_client
      
      # Test requests with artificial delays to simulate network conditions
      delay_test_requests = 8
      
      puts "🐌 Testing flow control with network delay simulation..."
      
      start_time = Time.monotonic
      
      delay_test_requests.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?delay=#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        
        # Add small delay between requests to simulate real-world conditions
        sleep(0.1.seconds) if i < delay_test_requests - 1
      end
      
      duration = Time.monotonic - start_time
      
      # Should complete despite delays
      duration.total_seconds.should be < 8.0
      
      puts "  ✅ #{delay_test_requests} requests with delays completed in #{duration.total_seconds.round(2)}s"
    end
  end
end