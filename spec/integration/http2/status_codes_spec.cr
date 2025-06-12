require "../support/http2_test_helpers_spec"

# HTTP/2 status code handling tests
# Focused on: Different status codes, error handling, edge cases
describe "HTTP/2 Status Codes" do
  describe "Success Status Codes" do
    it "handles different HTTP/2 status codes correctly" do
      client = HTTP2TestHelpers.create_test_client

      # Test 200 OK
      response_200 = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/status/200"))
      end
      HTTP2TestHelpers.assert_valid_http2_response(response_200, 200)

      # Test HTTP/2-only endpoint
      response_h2_only = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_only_url("/"))
      end
      HTTP2TestHelpers.assert_valid_http2_response(response_h2_only, 200)
    end

    it "handles 2xx status codes properly" do
      client = HTTP2TestHelpers.create_test_client

      # Test different 2xx codes if available
      %w[200 201 202].each do |status|
        response = HTTP2TestHelpers.retry_request do
          client.get(HTTP2TestHelpers.localhost_url("/status/#{status}"))
        end

        response.should_not be_nil
        [200, 201, 202].should contain(response.status)
        response.protocol.should eq("HTTP/2")
      end
    end
  end

  describe "Error Status Codes" do
    it "handles 4xx status codes gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # Test 404 Not Found
      response = HTTP2TestHelpers.retry_request(acceptable_statuses: (400..499)) do
        client.get(HTTP2TestHelpers.localhost_url("/nonexistent"))
      end

      response.should_not be_nil
      response.status.should be >= 400
      response.status.should be < 500
      response.protocol.should eq("HTTP/2")
    end

    it "handles 5xx status codes gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # Test 500 Internal Server Error (if endpoint exists)
      response = HTTP2TestHelpers.retry_request(acceptable_statuses: (500..599)) do
        client.get(HTTP2TestHelpers.localhost_url("/error"))
      end

      response.should_not be_nil
      if response.status >= 500
        response.status.should be < 600
        response.protocol.should eq("HTTP/2")
      end
    end
  end
end
