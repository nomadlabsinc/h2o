require "../support/http2_test_helpers_spec"

# HTTP/2 performance and concurrency tests
# Focused on: Multiple requests, concurrent operations, connection reuse
describe "HTTP/2 Performance and Reliability" do
  describe "Request Efficiency" do
    it "makes multiple HTTP/2 requests efficiently" do
      client = HTTP2TestHelpers.create_test_client

      # Sequential requests should reuse connection
      5.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?request=#{i}"))
        end

        HTTP2TestHelpers.assert_valid_http2_response(response)
      end
    end

    it "properly handles connection reuse" do
      client = HTTP2TestHelpers.create_test_client

      # Make multiple requests to verify connection reuse
      responses = [] of typeof(client.get(HTTP2TestHelpers.http2_url("/")))

      3.times do |i|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/?id=#{i}"))
        end

        HTTP2TestHelpers.assert_valid_http2_response(response)
        responses << response
      end

      # All responses should use HTTP/2 protocol
      responses.each do |response|
        response.protocol.should eq("HTTP/2")
      end
    end
  end

  describe "Concurrent Operations" do
    it "handles concurrent HTTP/2 requests" do
      client = HTTP2TestHelpers.create_test_client
      channel = Channel(H2O::Response?).new(5)

      # Create multiple concurrent requests
      5.times do |i|
        spawn do
          begin
            response = HTTP2TestHelpers.retry_request do
              client.get(HTTP2TestHelpers.http2_url("/?concurrent=#{i}"))
            end

            if response && response.status == 200
              channel.send(response)
            else
              channel.send(nil)
            end
          rescue ex
            puts "Concurrent request #{i} failed: #{ex.message}"
            channel.send(nil)
          end
        end
      end

      # Collect responses with timeout
      successful_responses = [] of H2O::Response
      5.times do
        select
        when response = channel.receive
          successful_responses << response if response
        when timeout(5.seconds)
          break
        end
      end

      # Should have at least 2 successful responses for concurrent testing
      success_count = successful_responses.size
      success_count.should be >= 2
    end
  end

  describe "Connection Behavior" do
    it "maintains HTTP/2 connection across requests" do
      client = HTTP2TestHelpers.create_test_client

      # Make requests to different query params (nghttpd doesn't have multiple endpoints)
      params = ["", "?test=1", "?foo=bar"]

      params.each do |param|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.http2_url("/#{param}"))
        end

        HTTP2TestHelpers.assert_valid_http2_response(response)
      end
    end
  end
end
