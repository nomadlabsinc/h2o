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

    it "encodes the problematic Zillow API URL correctly" do
      encoder = H2O::HPACK::Encoder.new

      # This is the actual URL that was failing
      path = "/api/v2/zestimates_v2/zestimates?address=1948+SW+Forest+Ridge+Ave%2C+Bend%2C+OR%2C+97702&access_token=REDACTED_ACCESS_TOKEN"

      headers = H2O::Headers{
        ":method"      => "GET",
        ":path"        => path,
        ":scheme"      => "https",
        ":authority"   => "api.bridgedataoutput.com",
        "accept"       => "application/json",
        "content-type" => "application/json",
        "user-agent"   => "H2O/2.0",
      }

      path.bytesize.should eq(134) # Verify the path length

      encoded = encoder.encode(headers)
      encoded.should_not be_empty

      # The total encoded size should be reasonable
      encoded.size.should be < 300

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
end
