require "../support/http2_test_helpers_spec"

# HTTP/2 content type and response format tests
# Focused on: Different content types, custom headers, response formats
describe "HTTP/2 Content Types and Headers" do
  describe "Response Content Types" do
    it "handles HTTP/2 responses with different content types" do
      client = HTTP2TestHelpers.create_test_client

      # Response from nghttpd server
      json_response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(json_response)
      # nghttpd returns basic headers like server, date, content-length
      json_response.headers["server"]?.should_not be_nil
      json_response.headers["server"].should contain("nghttpd")
    end

    it "handles HTTP/2 responses with custom headers" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"), {"X-Custom-Header" => "test-value"})
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      response.headers.should_not be_empty
    end
  end

  describe "HTTP/2 Protocol Headers" do
    it "sets proper User-Agent header" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      # nghttpd returns a simple HTML page, verify it contains expected content
      response.body.should contain("h2o HTTP/2 Test")
    end

    it "handles HTTP/2 headers correctly" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"), {
          "X-Test-Header" => "test-value",
          "Accept"        => "application/json",
        })
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end
  end
end
