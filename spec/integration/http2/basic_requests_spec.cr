require "../support/http2_test_helpers_spec"

# Basic HTTP/2 request functionality tests
# Focused on: GET, POST, PUT, DELETE operations
describe "HTTP/2 Basic Requests" do
  describe "HTTP/2 GET Requests" do
    it "successfully makes basic HTTP/2 GET requests" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      HTTP2TestHelpers.assert_response_contains(response, "h2o HTTP/2 Test")

      # Headers validation - nghttpd always sends server header
      response.headers.has_key?("server").should be_true
      response.headers["server"].should contain("nghttpd")
    end

    it "handles HTTP/2 GET requests with query parameters" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_url("/?param=value&test=123"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end
  end

  describe "HTTP/2 POST Requests" do
    it "successfully handles HTTP/2 POST requests with body" do
      client = HTTP2TestHelpers.create_test_client
      test_data = {message: "Hello HTTP/2"}.to_json

      response = HTTP2TestHelpers.retry_request do
        client.post(HTTP2TestHelpers.http2_url("/"), test_data, {"Content-Type" => "application/json"})
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      # nghttpd returns the same HTML page for all requests
      HTTP2TestHelpers.assert_response_contains(response, "h2o HTTP/2 Test")
    end

    it "handles HTTP/2 POST requests with form data" do
      client = HTTP2TestHelpers.create_test_client
      form_data = "name=test&value=123"

      response = HTTP2TestHelpers.retry_request do
        client.post(HTTP2TestHelpers.http2_url("/"), form_data, {"Content-Type" => "application/x-www-form-urlencoded"})
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end
  end
end
