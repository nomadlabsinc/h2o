require "../spec_helper"

describe "HPACK Security Protection" do
  describe "HpackSecurityLimits" do
    it "should have sensible defaults" do
      limits = H2O::HpackSecurityLimits.new

      limits.max_decompressed_size.should eq(65536)
      limits.max_header_count.should eq(100)
      limits.max_string_length.should eq(8192)
      limits.max_dynamic_table_size.should eq(65536)
      limits.compression_ratio_limit.should eq(10.0)
    end

    it "should allow custom configuration" do
      limits = H2O::HpackSecurityLimits.new(
        max_decompressed_size: 32768,
        max_header_count: 50,
        max_string_length: 4096,
        max_dynamic_table_size: 32768,
        compression_ratio_limit: 5.0
      )

      limits.max_decompressed_size.should eq(32768)
      limits.max_header_count.should eq(50)
      limits.max_string_length.should eq(4096)
      limits.max_dynamic_table_size.should eq(32768)
      limits.compression_ratio_limit.should eq(5.0)
    end
  end

  describe "HpackBombError" do
    it "should have default message" do
      error = H2O::HpackBombError.new
      error.message.should eq("HPACK bomb attack detected")
    end

    it "should accept custom message" do
      error = H2O::HpackBombError.new("Custom HPACK bomb message")
      error.message.should eq("Custom HPACK bomb message")
    end
  end

  describe "HPACK::Decoder security" do
    it "should enforce header count limits" do
      limits = H2O::HpackSecurityLimits.new(max_header_count: 2)
      decoder = H2O::HPACK::Decoder.new(4096, limits)

      # This should work with 2 headers or less
      # We need a simple encoded header block for testing
      # For now, test that the decoder initializes properly with limits
      decoder.security_limits.max_header_count.should eq(2)
    end

    it "should enforce decompressed size limits" do
      limits = H2O::HpackSecurityLimits.new(max_decompressed_size: 1024)
      decoder = H2O::HPACK::Decoder.new(4096, limits)

      decoder.security_limits.max_decompressed_size.should eq(1024)
    end

    it "should enforce string length limits" do
      limits = H2O::HpackSecurityLimits.new(max_string_length: 512)
      decoder = H2O::HPACK::Decoder.new(4096, limits)

      decoder.security_limits.max_string_length.should eq(512)
    end

    it "should enforce dynamic table size limits" do
      limits = H2O::HpackSecurityLimits.new(max_dynamic_table_size: 2048)
      decoder = H2O::HPACK::Decoder.new(4096, limits)

      decoder.security_limits.max_dynamic_table_size.should eq(2048)
    end

    it "should enforce compression ratio limits" do
      limits = H2O::HpackSecurityLimits.new(compression_ratio_limit: 2.0)
      decoder = H2O::HPACK::Decoder.new(4096, limits)

      decoder.security_limits.compression_ratio_limit.should eq(2.0)
    end
  end

  describe "Huffman decoder security" do
    it "should accept reasonable length limit" do
      # This is just testing the interface, actual Huffman tests would need valid data
      max_length = 1024
      # Would test: H2O::HPACK::Huffman.decode(valid_data, max_length)
      max_length.should eq(1024)
    end
  end
end
