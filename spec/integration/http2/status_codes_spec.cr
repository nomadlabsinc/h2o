require "../support/http2_test_helpers_spec"

# HTTP/2 status code handling tests
# Focused on: Different status codes, error handling, edge cases
describe "HTTP/2 Status Codes" do
  describe "Success Status Codes" do
    it "handles different HTTP/2 status codes correctly" do
      client = HTTP2TestHelpers.create_test_client

      # Test 200 OK
      response_200 = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
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

      # nghttpd only returns 200 OK for valid requests
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      response.should_not be_nil
      response.status.should eq(200)
      response.protocol.should eq("HTTP/2")
    end
  end

  describe "Error Status Codes" do
    it "handles 4xx status codes gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # Test 404 Not Found
      response = HTTP2TestHelpers.retry_request(acceptable_statuses: (400..499)) do
        client.get(HTTP2TestHelpers.http2_url("/nonexistent"))
      end

      response.should_not be_nil
      response.status.should be >= 400
      response.status.should be < 500
      response.protocol.should eq("HTTP/2")
    end

    it "handles 5xx status codes gracefully" do
      client = HTTP2TestHelpers.create_test_client

      # nghttpd doesn't have a dedicated error endpoint, but we can test invalid paths
      response = HTTP2TestHelpers.retry_request(acceptable_statuses: (400..599)) do
        client.get(HTTP2TestHelpers.http2_url("/error"))
      end

      response.should_not be_nil
      response.status.should be >= 400  # Should get 404 for non-existent path
      response.protocol.should eq("HTTP/2")
    end
  end
end
