require "../support/http2_test_helpers_spec"

# Simple focused test for the WINDOW_UPDATE flow control fix
# Tests the specific issue that caused connection hangs after ~14 requests
describe "HTTP/2 WINDOW_UPDATE Fix Verification" do
  it "successfully handles 20 consecutive requests without hanging" do
    client = HTTP2TestHelpers.create_test_client
    
    # This would previously cause connection hangs after ~14 requests
    # due to flow control window exhaustion
    request_count = 20
    
    puts "Testing #{request_count} consecutive requests..."
    start_time = Time.monotonic
    
    successful_count = 0
    
    request_count.times do |i|
      begin
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/test/#{i}"))
        end
        
        HTTP2TestHelpers.assert_valid_http2_response(response)
        successful_count += 1
        
        # Log progress at critical points
        if i == 13
          puts "✓ Passed request 14 (was problematic before fix)"
        elsif i == 19
          puts "✓ All 20 requests completed successfully"
        end
        
      rescue ex : Exception
        puts "❌ Request #{i + 1} failed: #{ex.message}"
        raise ex
      end
    end
    
    duration = Time.monotonic - start_time
    
    # All requests should succeed
    successful_count.should eq(request_count)
    
    # Should complete quickly, not timeout at 30 seconds
    duration.total_seconds.should be < 10.0
    
    puts "✅ Flow control fix verified: #{successful_count}/#{request_count} requests successful in #{duration.total_seconds.round(2)}s"
    puts "   Average: #{(duration.total_milliseconds / successful_count).round(2)}ms per request"
  end
  
  it "handles rapid sequential requests without flow control issues" do
    client = HTTP2TestHelpers.create_test_client
    
    # Test rapid requests that would quickly exhaust flow control window
    rapid_count = 15
    
    puts "Testing #{rapid_count} rapid sequential requests..."
    start_time = Time.monotonic
    
    responses = [] of H2O::Response
    
    rapid_count.times do |i|
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/rapid/#{i}"))
      end
      
      HTTP2TestHelpers.assert_valid_http2_response(response)
      responses << response
    end
    
    duration = Time.monotonic - start_time
    
    responses.size.should eq(rapid_count)
    duration.total_seconds.should be < 5.0
    
    puts "✅ Rapid requests completed: #{responses.size}/#{rapid_count} in #{duration.total_seconds.round(2)}s"
  end
end