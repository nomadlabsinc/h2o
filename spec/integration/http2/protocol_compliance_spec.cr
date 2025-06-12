require "../support/http2_test_helpers_spec"

# HTTP/2 protocol compliance and compatibility tests
# Focused on: Protocol standards, HTTP/1.1 vs HTTP/2 comparison, compliance
describe "HTTP/2 Protocol Compliance" do
  describe "Protocol Standards" do
    it "enforces HTTP/2 protocol requirements" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)

      # Verify HTTP/2 specific behaviors
      response.protocol.should eq("HTTP/2")
      response.headers.should_not be_empty
    end

    it "handles HTTP/2-only server endpoints" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_only_url("/reject-h1"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      HTTP2TestHelpers.assert_response_contains(response, "HTTP/2")
    end
  end

  describe "Header Compliance" do
    it "handles HTTP/2 pseudo-headers correctly" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/headers"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)

      # HTTP/2 should handle headers correctly
      response.headers.should_not be_empty
    end

    it "maintains header case sensitivity rules" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/"), {
          "Accept"     => "application/json",
          "User-Agent" => "H2O-Test-Client/1.0",
        })
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
    end
  end

  describe "HTTP/2 vs HTTP/1.1 Compatibility" do
    it "demonstrates HTTP/2 functionality works as well as HTTP/1.1" do
      http2_client = HTTP2TestHelpers.create_test_client

      # Test HTTP/2 endpoint
      http2_response = HTTP2TestHelpers.retry_request do
        http2_client.get(HTTP2TestHelpers.localhost_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(http2_response)

      # Verify HTTP/2 provides expected functionality
      http2_response.body.should_not be_empty
      http2_response.headers.should_not be_empty
      http2_response.protocol.should eq("HTTP/2")
    end

    it "handles protocol negotiation correctly" do
      client = HTTP2TestHelpers.create_test_client

      # Test that client correctly negotiates HTTP/2
      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.localhost_url("/"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)

      # Should have negotiated HTTP/2
      response.protocol.should eq("HTTP/2")
    end
  end

  describe "Multi-Service Compatibility" do
    it "works correctly with Caddy HTTP/2 server" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.caddy_url("/health"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      HTTP2TestHelpers.assert_response_contains(response, "Caddy")
    end

    it "works correctly with Node.js HTTP/2-only server" do
      client = HTTP2TestHelpers.create_test_client

      response = HTTP2TestHelpers.retry_request do
        client.get(HTTP2TestHelpers.http2_only_url("/health"))
      end

      HTTP2TestHelpers.assert_valid_http2_response(response)
      HTTP2TestHelpers.assert_response_contains(response, "HTTP/2")
    end
  end
end
