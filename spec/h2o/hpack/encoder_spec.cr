require "../../spec_helper"

describe H2O::HPACK::Encoder do
  describe "#encode" do
    it "encodes headers with short values correctly" do
      encoder = H2O::HPACK::Encoder.new
      headers = H2O::Headers{
        ":method"    => "GET",
        ":path"      => "/test",
        ":scheme"    => "https",
        ":authority" => "example.com",
      }

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify it can be decoded
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
    end

    it "encodes headers with values longer than 255 bytes" do
      encoder = H2O::HPACK::Encoder.new
      long_path = "/api/v2/test?" + "param=value&" * 25 # Creates a path > 255 bytes

      headers = H2O::Headers{
        ":method"    => "GET",
        ":path"      => long_path,
        ":scheme"    => "https",
        ":authority" => "example.com",
      }

      long_path.bytesize.should be > 255

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify it can be decoded correctly
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
      decoded[":path"].should eq(long_path)
    end

    it "encodes headers with very long values (>1000 bytes)" do
      encoder = H2O::HPACK::Encoder.new
      very_long_value = "x" * 1500

      headers = H2O::Headers{
        ":method"       => "POST",
        ":path"         => "/upload",
        ":scheme"       => "https",
        ":authority"    => "example.com",
        "x-custom-data" => very_long_value,
      }

      very_long_value.bytesize.should eq(1500)

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify it can be decoded correctly
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
      decoded["x-custom-data"].should eq(very_long_value)
    end

    it "encodes URLs with query parameters correctly" do
      encoder = H2O::HPACK::Encoder.new

      # Test with a realistic URL with query parameters (no sensitive data)
      path = "/api/v2/endpoint?param1=value1&param2=value2&address=123+Main+St%2C+City%2C+State%2C+12345"

      headers = H2O::Headers{
        ":method"      => "GET",
        ":path"        => path,
        ":scheme"      => "https",
        ":authority"   => "api.example.com",
        "accept"       => "application/json",
        "content-type" => "application/json",
        "user-agent"   => "H2O/2.0",
      }

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify it can be decoded correctly
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
    end

    it "handles headers with long names correctly" do
      encoder = H2O::HPACK::Encoder.new
      long_header_name = "x-very-long-custom-header-name-" + "a" * 300

      headers = H2O::Headers{
        ":method"        => "GET",
        ":path"          => "/test",
        ":scheme"        => "https",
        ":authority"     => "example.com",
        long_header_name => "value",
      }

      long_header_name.bytesize.should be > 255

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify it can be decoded correctly
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
      decoded[long_header_name].should eq("value")
    end

    it "encodes multiple headers with mixed sizes correctly" do
      encoder = H2O::HPACK::Encoder.new

      headers = H2O::Headers{
        ":method"       => "POST",
        ":path"         => "/api/endpoint/with/a/reasonably/long/path/that/is/still/under/255/bytes",
        ":scheme"       => "https",
        ":authority"    => "api.example.com",
        "authorization" => "Bearer " + "a" * 300, # Long auth token
        "x-short"       => "1",
        "x-medium"      => "This is a medium length header value",
        "x-long"        => "L" * 500,
      }

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify round-trip encoding/decoding
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)
    end
  end

  describe "encode_header_simple" do
    it "uses proper encoding for all header types" do
      encoder = H2O::HPACK::Encoder.new

      # Test that common static headers use indexed representation
      static_headers = H2O::Headers{
        ":method" => "GET",
        ":scheme" => "https",
        ":status" => "200",
      }

      encoded = encoder.encode(static_headers)

      # Static headers should result in very compact encoding
      encoded.size.should be < 10

      # Test that custom headers use literal encoding
      custom_headers = H2O::Headers{
        "x-custom"  => "value",
        "x-api-key" => "secret",
      }

      encoded_custom = encoder.encode(custom_headers)

      # Custom headers need full literal encoding
      encoded_custom.size.should be > 20
    end
  end

  describe "regression tests" do
    it "properly encodes string lengths using HPACK integer encoding (issue #50)" do
      # This test prevents regression of the HPACK encoding bug where invalid single-byte
      # length encoding was causing Google APIs to reject requests with CompressionError
      encoder = H2O::HPACK::Encoder.new

      # Test with headers that don't match static table entries
      # These headers were failing with Google Maps API due to invalid length encoding
      headers = H2O::Headers{
        ":method"    => "GET",
        ":path"      => "/maps/api/place/nearbysearch/json",
        ":scheme"    => "https",
        ":authority" => "maps.googleapis.com",
        "accept"     => "application/json", # This header triggers literal encoding
        "user-agent" => "H2O/2.0",
      }

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # Verify round-trip encoding/decoding works correctly
      decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)
      decoded = decoder.decode(encoded)
      decoded.should eq(headers)

      # Test encode_fast method specifically (where the bug was)
      fast_encoded = H2O::HPACK.encode_fast(headers)
      fast_encoded.should_not be_empty

      # Verify fast encoding can also be decoded correctly
      fast_decoded = decoder.decode(fast_encoded)
      fast_decoded.should eq(headers)
    end

    it "properly encodes headers with long values using HPACK integer encoding" do
      # Test with various string lengths to ensure proper HPACK integer encoding
      encoder = H2O::HPACK::Encoder.new

      test_cases = [
        {"short", "x"},               # 1 byte value
        {"medium", "x" * 126},        # 126 bytes (near single-byte limit)
        {"boundary", "x" * 127},      # 127 bytes (exactly at 7-bit limit)
        {"over_boundary", "x" * 128}, # 128 bytes (requires multi-byte encoding)
        {"large", "x" * 255},         # 255 bytes
        {"very_large", "x" * 1000},   # 1000 bytes
      ]

      test_cases.each do |name, value|
        headers = H2O::Headers{
          ":method"        => "GET",
          ":path"          => "/test",
          ":scheme"        => "https",
          ":authority"     => "example.com",
          "x-test-#{name}" => value,
        }

        # Test both encoder methods
        encoded = encoder.encode(headers)
        encoded.should_not be_empty

        fast_encoded = H2O::HPACK.encode_fast(headers)
        fast_encoded.should_not be_empty

        # Verify both can be decoded correctly
        decoder = H2O::HPACK::Decoder.new(4096, H2O::HpackSecurityLimits.new)

        decoded = decoder.decode(encoded)
        decoded.should eq(headers)
        decoded["x-test-#{name}"].should eq(value)

        fast_decoded = decoder.decode(fast_encoded)
        fast_decoded.should eq(headers)
        fast_decoded["x-test-#{name}"].should eq(value)
      end
    end
  end
end
