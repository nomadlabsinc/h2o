require "../support/http2_test_helpers_spec"

# HTTP/2 content type and response format tests
# Focused on: Different content types, custom headers, response formats
describe "HTTP/2 Content Types and Headers" do
  describe "Response Content Types" do
    it "handles HTTP/2 responses with different content types" do
      client = HTTP2TestHelpers.create_test_client

      # JSON response from local server
      json_response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(json_response)
      json_response.headers["content-type"]?.should_not be_nil
    end

    it "handles HTTP/2 responses with custom headers" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/"), {"X-Custom-Header" => "test-value"})
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      response.headers.should_not be_empty
    end
  end

  describe "HTTP/2 Protocol Headers" do
    it "sets proper User-Agent header" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/headers"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      # The response should contain information about the User-Agent header
      response.body.should contain("user-agent")
    end

    it "handles HTTP/2 headers correctly" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/headers"), {
          "X-Test-Header" => "test-value",
          "Accept"        => "application/json",
        })
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end
  end
end
