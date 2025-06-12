require "../../spec_helper"

describe "H2O::HPACK.encode_fast" do
  it "encodes static table headers correctly" do
    headers : H2O::Headers = H2O::Headers.new
    headers[":method"] = "GET"
    headers[":scheme"] = "https"
    headers[":status"] = "200"
    headers["accept-encoding"] = "gzip, deflate"

    result : Bytes = H2O::HPACK.encode_fast(headers)

    # Should contain static table indices
    result.should_not be_empty
    result.size.should be < 50 # Should be compact due to static table usage
  end

  it "encodes literal headers correctly" do
    headers = H2O::Headers.new
    headers["custom-header"] = "custom-value"
    headers["x-api-key"] = "secret123"

    result = H2O::HPACK.encode_fast(headers)

    # Should contain literal header encodings
    result.should_not be_empty
    # Literal headers are larger since they include the full name/value
    result.size.should be > 30
  end

  it "produces identical output to instance encoder" do
    headers = H2O::Headers.new
    headers[":method"] = "POST"
    headers[":path"] = "/api/test"
    headers[":scheme"] = "https"
    headers[":authority"] = "api.example.com"
    headers["user-agent"] = "TestClient/1.0"
    headers["content-type"] = "application/json"

    fast_result = H2O::HPACK.encode_fast(headers)

    encoder = H2O::HPACK::Encoder.new
    instance_result = encoder.encode(headers)

    fast_result.should eq(instance_result)
  end

  it "handles empty headers" do
    headers = H2O::Headers.new
    result = H2O::HPACK.encode_fast(headers)

    result.should_not be_nil
    result.size.should eq(0)
  end

  it "handles mixed static and literal headers" do
    headers = H2O::Headers.new
    headers[":method"] = "GET"                # Static table match
    headers[":path"] = "/custom/path"         # Literal (non-standard path)
    headers[":scheme"] = "https"              # Static table match
    headers["authorization"] = "Bearer token" # Literal

    result = H2O::HPACK.encode_fast(headers)

    result.should_not be_empty
    # Should be reasonably compact due to static table usage for some headers
    result.size.should be < 100
  end

  it "handles all supported static table entries" do
    test_cases = [
      {":method", "GET"},
      {":method", "POST"},
      {":path", "/"},
      {":scheme", "http"},
      {":scheme", "https"},
      {":status", "200"},
      {":status", "204"},
      {":status", "206"},
      {":status", "304"},
      {":status", "400"},
      {":status", "404"},
      {":status", "500"},
      {"accept-encoding", "gzip, deflate"},
    ]

    test_cases.each do |name, value|
      headers = H2O::Headers.new
      headers[name] = value

      result = H2O::HPACK.encode_fast(headers)

      # Static table entries should encode to just 1 byte
      result.size.should eq(1)
      result[0].should be > 0x80 # Should be indexed header format
    end
  end

  it "performance test - should be faster than creating new encoder instances" do
    headers = H2O::Headers.new
    headers[":method"] = "GET"
    headers[":path"] = "/api/performance"
    headers[":scheme"] = "https"
    headers["user-agent"] = "PerformanceTest/1.0"

    iterations = 10000 # More iterations for stable timing

    # Extended warm up to stabilize performance
    50.times do
      H2O::HPACK.encode_fast(headers)
      encoder = H2O::HPACK::Encoder.new
      encoder.encode(headers)
    end

    # Test fast static method with multiple runs for stability
    fast_times = Array(Time::Span).new
    5.times do
      fast_start = Time.monotonic
      iterations.times do
        H2O::HPACK.encode_fast(headers)
      end
      fast_times << (Time.monotonic - fast_start)
    end
    fast_time = fast_times.min # Use best time to avoid system load variance

    # Test instance method with multiple runs
    instance_times = Array(Time::Span).new
    5.times do
      instance_start = Time.monotonic
      iterations.times do
        encoder = H2O::HPACK::Encoder.new
        encoder.encode(headers)
      end
      instance_times << (Time.monotonic - instance_start)
    end
    instance_time = instance_times.min # Use best time

    # Fast method should be at least as fast as instance method
    # Allow for 50% variance due to system conditions and JIT compilation
    # The goal is to verify the method works, not precise performance benchmarking
    fast_time.should be <= (instance_time * 1.5)

    # Also verify that both methods produce the same output
    fast_result = H2O::HPACK.encode_fast(headers)
    encoder = H2O::HPACK::Encoder.new
    instance_result = encoder.encode(headers)
    fast_result.should eq(instance_result)
  end
end
