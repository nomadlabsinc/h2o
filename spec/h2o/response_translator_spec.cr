require "../spec_helper"

describe H2O::ResponseTranslator do
  after_each do
    GlobalStateHelper.clear_all_caches
  end

  describe "#initialize" do
    it "creates translator with HPACK decoder" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)
      translator.should_not be_nil
    end
  end

  describe "#process_headers_frame" do
    it "processes HEADERS frame with status code" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Create a simple HEADERS frame with encoded headers
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-type"] = "application/json"
      headers["content-length"] = "25"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      translator.process_headers_frame(headers_frame)

      translator.status.should eq(200)
      translator.headers["content-type"].should eq("application/json")
      translator.headers["content-length"].should eq("25")
      translator.headers_complete?.should be_true
      translator.data_complete?.should be_false
    end

    it "processes HEADERS frame with END_STREAM flag" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "204"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS | H2O::HeadersFrame::FLAG_END_STREAM
      )

      translator.process_headers_frame(headers_frame)

      translator.status.should eq(204)
      translator.headers_complete?.should be_true
      translator.data_complete?.should be_true
      translator.response_complete?.should be_true
    end

    it "extracts status code from :status pseudo-header" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "404"
      headers["content-type"] = "text/html"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      translator.process_headers_frame(headers_frame)

      translator.status.should eq(404)
      translator.headers["content-type"].should eq("text/html")
      # Should not include pseudo-headers in final headers
      translator.headers.has_key?(":status").should be_false
    end

    it "filters out pseudo-headers from final headers" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers[":custom-pseudo"] = "should-be-filtered"
      headers["real-header"] = "should-be-kept"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      translator.process_headers_frame(headers_frame)

      translator.headers.has_key?(":status").should be_false
      translator.headers.has_key?(":custom-pseudo").should be_false
      translator.headers["real-header"].should eq("should-be-kept")
    end
  end

  describe "#process_data_frame" do
    it "processes DATA frame and appends to body" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      data_content = "Hello, World!"
      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: data_content.to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )

      translator.process_data_frame(data_frame)

      translator.body.should eq("Hello, World!")
      translator.data_complete?.should be_true
    end

    it "processes multiple DATA frames and concatenates body" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # First DATA frame
      data_frame1 = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: "Hello, ".to_slice,
        flags: 0_u8
      )

      # Second DATA frame
      data_frame2 = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: "World!".to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )

      translator.process_data_frame(data_frame1)
      translator.data_complete?.should be_false
      translator.body.should eq("Hello, ")

      translator.process_data_frame(data_frame2)
      translator.data_complete?.should be_true
      translator.body.should eq("Hello, World!")
    end

    it "handles empty DATA frames" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      empty_data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: Bytes.empty,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )

      translator.process_data_frame(empty_data_frame)

      translator.body.should eq("")
      translator.data_complete?.should be_true
    end

    it "handles unicode content in DATA frames" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      unicode_content = "Hello 世界! 🌍"
      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: unicode_content.to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )

      translator.process_data_frame(data_frame)

      translator.body.should eq("Hello 世界! 🌍")
    end
  end

  describe "#build_response" do
    it "builds complete response from headers and data" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Process headers
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-type"] = "application/json"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )
      translator.process_headers_frame(headers_frame)

      # Process data
      data_content = "{\"message\":\"success\"}"
      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: data_content.to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )
      translator.process_data_frame(data_frame)

      # Build response
      response = translator.build_response

      response.should be_a(H2O::Response)
      response.status.should eq(200)
      response.headers["content-type"].should eq("application/json")
      response.body.should eq("{\"message\":\"success\"}")
      response.protocol.should eq("HTTP/2")
    end

    it "raises error when response is not complete" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Only process headers, no END_STREAM
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )
      translator.process_headers_frame(headers_frame)

      expect_raises(ArgumentError, "Response is not complete - cannot build Response object") do
        translator.build_response
      end
    end

    it "raises error when status code is missing" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Process headers without :status
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers["content-type"] = "text/plain"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS | H2O::HeadersFrame::FLAG_END_STREAM
      )
      translator.process_headers_frame(headers_frame)

      expect_raises(ArgumentError, "Missing :status pseudo-header in response") do
        translator.build_response
      end
    end
  end

  describe "#reset" do
    it "resets translator state for reuse" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Process some data first
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-type"] = "text/plain"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )
      translator.process_headers_frame(headers_frame)

      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: "test data".to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )
      translator.process_data_frame(data_frame)

      # Verify state before reset
      translator.status.should eq(200)
      translator.body.should eq("test data")
      translator.response_complete?.should be_true

      # Reset
      translator.reset

      # Verify state after reset
      translator.status.should eq(0)
      translator.body.should eq("")
      translator.headers.empty?.should be_true
      translator.headers_complete?.should be_false
      translator.data_complete?.should be_false
      translator.response_complete?.should be_false
    end
  end

  describe "#statistics" do
    it "returns response statistics" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Process headers and data
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "201"
      headers["content-type"] = "application/json"
      headers["x-custom"] = "value"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )
      translator.process_headers_frame(headers_frame)

      data_content = "response body content"
      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: data_content.to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )
      translator.process_data_frame(data_frame)

      stats = translator.statistics

      stats[:status_code].should eq(201)
      stats[:headers_count].should eq(2) # content-type and x-custom (no pseudo-headers)
      stats[:body_size].should eq(data_content.bytesize)
      stats[:headers_complete].should be_true
      stats[:data_complete].should be_true
      stats[:response_ready].should be_true
    end
  end

  describe ".translate_frames (static method)" do
    it "translates array of frames to response" do
      decoder = H2O::HPACK::Decoder.new

      # Create frames
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-type"] = "text/plain"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: "static method test".to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )

      frames = [headers_frame.as(H2O::Frame), data_frame.as(H2O::Frame)]
      response = H2O::ResponseTranslator.translate_frames(frames, decoder)

      response.status.should eq(200)
      response.headers["content-type"].should eq("text/plain")
      response.body.should eq("static method test")
      response.protocol.should eq("HTTP/2")
    end

    it "ignores non-headers/data frames" do
      decoder = H2O::HPACK::Decoder.new

      # Create frames including a PING frame that should be ignored
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS | H2O::HeadersFrame::FLAG_END_STREAM
      )

      ping_frame = H2O::PingFrame.new

      frames = [headers_frame.as(H2O::Frame), ping_frame.as(H2O::Frame)]
      response = H2O::ResponseTranslator.translate_frames(frames, decoder)

      response.status.should eq(200)
      response.body.should eq("")
    end
  end

  describe "error handling" do
    it "handles invalid status code values" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "invalid"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      expect_raises(ArgumentError, "Invalid :status pseudo-header value: invalid") do
        translator.process_headers_frame(headers_frame)
      end
    end

    it "handles out-of-range status codes" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "99" # Below valid range

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      expect_raises(ArgumentError, "Invalid :status pseudo-header value: 99") do
        translator.process_headers_frame(headers_frame)
      end
    end

    it "creates error response for invalid frames" do
      error_response = H2O::ResponseTranslator.create_error_response("Test error", 500)

      error_response.status.should eq(500)
      error_response.body.should eq("Test error")
      error_response.protocol.should eq("HTTP/2")
      error_response.headers.empty?.should be_true
    end

    it "creates error response with default status code" do
      error_response = H2O::ResponseTranslator.create_error_response("Default error")

      error_response.status.should eq(500)
      error_response.body.should eq("Default error")
    end
  end

  describe "frame validation" do
    it "validates headers frame has non-empty header block" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Create headers frame with empty header block
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: Bytes.empty,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )

      expect_raises(ArgumentError, "HEADERS frame cannot have empty header block") do
        translator.process_headers_frame(headers_frame)
      end
    end
  end

  describe "complete response workflow" do
    it "handles typical successful response workflow" do
      decoder = H2O::HPACK::Decoder.new
      translator = H2O::ResponseTranslator.new(decoder)

      # Step 1: Process headers
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-type"] = "application/json"
      headers["content-length"] = "13"

      encoded_headers = encoder.encode(headers)
      headers_frame = H2O::HeadersFrame.new(
        stream_id: 1_u32,
        header_block: encoded_headers,
        flags: H2O::HeadersFrame::FLAG_END_HEADERS
      )
      translator.process_headers_frame(headers_frame)

      # Verify intermediate state
      translator.headers_complete?.should be_true
      translator.data_complete?.should be_false
      translator.response_complete?.should be_false

      # Step 2: Process data
      data_content = "{\"ok\":true}"
      data_frame = H2O::DataFrame.new(
        stream_id: 1_u32,
        data: data_content.to_slice,
        flags: H2O::DataFrame::FLAG_END_STREAM
      )
      translator.process_data_frame(data_frame)

      # Verify final state
      translator.headers_complete?.should be_true
      translator.data_complete?.should be_true
      translator.response_complete?.should be_true

      # Step 3: Build response
      response = translator.build_response

      response.status.should eq(200)
      response.headers["content-type"].should eq("application/json")
      response.headers["content-length"].should eq("13")
      response.body.should eq("{\"ok\":true}")
      response.protocol.should eq("HTTP/2")
      response.success?.should be_true
    end
  end
end
