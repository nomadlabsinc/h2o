require "../spec_helper"

describe H2O::RequestTranslator do
  after_each do
    GlobalStateHelper.clear_all_caches
  end

  describe "#initialize" do
    it "creates translator with HPACK encoder" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      translator.should_not be_nil
    end
  end

  describe "#translate" do
    it "translates GET request to HTTP/2 frames" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      headers["user-agent"] = "h2o-client"

      request = H2O::Request.new("GET", "/test", headers)
      stream_id = 1_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      headers_frame.should be_a(H2O::HeadersFrame)
      headers_frame.stream_id.should eq(stream_id)
      headers_frame.end_headers?.should be_true
      headers_frame.end_stream?.should be_true # No body, so END_STREAM

      data_frame.should be_nil # No body for GET request
    end

    it "translates POST request with body to HTTP/2 frames" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      headers["content-type"] = "application/json"

      request = H2O::Request.new("POST", "/api/test", headers, "{\"key\":\"value\"}")
      stream_id = 3_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      headers_frame.should be_a(H2O::HeadersFrame)
      headers_frame.stream_id.should eq(stream_id)
      headers_frame.end_headers?.should be_true
      headers_frame.end_stream?.should be_false # Has body, so no END_STREAM on headers

      data_frame.should be_a(H2O::DataFrame)
      data_frame.should_not be_nil
      data_frame.not_nil!.stream_id.should eq(stream_id)
      data_frame.not_nil!.end_stream?.should be_true
      String.new(data_frame.not_nil!.data).should eq("{\"key\":\"value\"}")
    end

    it "includes all required HTTP/2 pseudo-headers" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "api.example.com"
      headers["authorization"] = "Bearer token123"

      request = H2O::Request.new("PUT", "/v1/resource/123", headers)
      stream_id = 5_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      # Decode the headers to verify pseudo-headers
      decoder = H2O::HPACK::Decoder.new
      decoded_headers = decoder.decode(headers_frame.header_block)

      # Verify pseudo-headers are present and correct
      decoded_headers[":method"].should eq("PUT")
      decoded_headers[":path"].should eq("/v1/resource/123")
      decoded_headers[":scheme"].should eq("https")
      decoded_headers[":authority"].should eq("api.example.com")

      # Verify regular headers (excluding host which becomes :authority)
      decoded_headers["authorization"].should eq("Bearer token123")
      decoded_headers.has_key?("host").should be_false
    end
  end

  describe "#create_headers_frame (alternative method)" do
    it "creates headers frame from individual components" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "test.example.com"
      headers["accept"] = "application/json"

      stream_id = 9_u32
      headers_frame = translator.create_headers_frame(
        stream_id, "GET", "/api/data", headers, nil
      )

      headers_frame.should be_a(H2O::HeadersFrame)
      headers_frame.stream_id.should eq(stream_id)
      headers_frame.end_headers?.should be_true
      headers_frame.end_stream?.should be_true # No body

      decoder = H2O::HPACK::Decoder.new
      decoded_headers = decoder.decode(headers_frame.header_block)

      decoded_headers[":method"].should eq("GET")
      decoded_headers[":path"].should eq("/api/data")
      decoded_headers[":authority"].should eq("test.example.com")
      decoded_headers["accept"].should eq("application/json")
    end

    it "creates headers frame with body indication" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "api.test.com"

      stream_id = 11_u32
      headers_frame = translator.create_headers_frame(
        stream_id, "POST", "/submit", headers, "request body"
      )

      headers_frame.end_stream?.should be_false # Has body
    end
  end

  describe "#create_data_frame" do
    it "creates data frame from body string" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      body = "This is the request body content"
      stream_id = 13_u32

      data_frame = translator.create_data_frame(stream_id, body)

      data_frame.should be_a(H2O::DataFrame)
      data_frame.stream_id.should eq(stream_id)
      data_frame.end_stream?.should be_true
      data_frame.length.should eq(body.bytesize)
      String.new(data_frame.data).should eq(body)
    end

    it "handles empty body" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      body = ""
      stream_id = 15_u32

      data_frame = translator.create_data_frame(stream_id, body)

      data_frame.length.should eq(0)
      data_frame.data.size.should eq(0)
    end

    it "handles unicode content" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      body = "Hello 世界! 🌍"
      stream_id = 17_u32

      data_frame = translator.create_data_frame(stream_id, body)

      data_frame.length.should eq(body.bytesize)
      String.new(data_frame.data).should eq(body)
    end
  end

  describe "#validate_request" do
    it "validates valid request successfully" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "valid.example.com"

      request = H2O::Request.new("GET", "/valid/path", headers)

      # Should not raise
      translator.validate_request(request)
    end

    it "raises error for empty method" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      request = H2O::Request.new("", "/path", headers)

      expect_raises(ArgumentError, "Request method cannot be empty") do
        translator.validate_request(request)
      end
    end

    it "raises error for missing host header" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new

      request = H2O::Request.new("GET", "/path", headers)

      expect_raises(ArgumentError, "Missing host header - required for HTTP/2 :authority pseudo-header") do
        translator.validate_request(request)
      end
    end

    it "accepts all valid HTTP methods" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      valid_methods = %w[GET POST PUT DELETE HEAD OPTIONS PATCH TRACE CONNECT]

      valid_methods.each do |method|
        request = H2O::Request.new(method, "/path", headers)
        # Should not raise
        translator.validate_request(request)
      end
    end
  end

  describe "header processing" do
    it "extracts host header correctly and converts to lowercase" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["Host"] = "Example.com"
      headers["Content-Type"] = "application/json"

      request = H2O::Request.new("GET", "/", headers)
      stream_id = 19_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      decoder = H2O::HPACK::Decoder.new
      decoded_headers = decoder.decode(headers_frame.header_block)

      decoded_headers[":authority"].should eq("Example.com")
      decoded_headers["content-type"].should eq("application/json")
      decoded_headers.has_key?("host").should be_false
      decoded_headers.has_key?("Host").should be_false
    end
  end

  describe "frame flags" do
    it "sets END_STREAM and END_HEADERS for request without body" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      request = H2O::Request.new("GET", "/", headers)
      stream_id = 33_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      headers_frame.end_stream?.should be_true
      headers_frame.end_headers?.should be_true
      data_frame.should be_nil
    end

    it "sets only END_HEADERS for request with body" do
      encoder = H2O::HPACK::Encoder.new
      translator = H2O::RequestTranslator.new(encoder)
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      request = H2O::Request.new("POST", "/", headers, "body")
      stream_id = 35_u32

      headers_frame, data_frame = translator.translate(request, stream_id)

      headers_frame.end_stream?.should be_false
      headers_frame.end_headers?.should be_true

      data_frame.should_not be_nil
      data_frame.not_nil!.end_stream?.should be_true
    end
  end
end
