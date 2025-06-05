require "../../spec_helper"

describe "HPACK Huffman Performance" do
  describe "encode and decode optimizations" do
    it "correctly encodes and decodes with buffer pooling" do
      test_string = "Hello, World! This is a test string for Huffman encoding."

      encoded = H2O::HPACK::Huffman.encode(test_string)
      encoded.should_not be_empty

      decoded = H2O::HPACK::Huffman.decode(encoded)
      decoded.should eq(test_string)
    end

    it "handles empty strings correctly" do
      encoded = H2O::HPACK::Huffman.encode("")
      decoded = H2O::HPACK::Huffman.decode(encoded)
      decoded.should eq("")
    end

    it "handles special characters correctly" do
      test_string = "Content-Type: application/json; charset=UTF-8"

      encoded = H2O::HPACK::Huffman.encode(test_string)
      decoded = H2O::HPACK::Huffman.decode(encoded)
      decoded.should eq(test_string)
    end

    it "performs correctly with repeated encoding/decoding" do
      test_strings = [
        "www.example.com",
        "GET",
        "POST",
        "application/json",
        "gzip, deflate, br",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      ]

      test_strings.each do |test_string|
        encoded = H2O::HPACK::Huffman.encode(test_string)
        decoded = H2O::HPACK::Huffman.decode(encoded)
        decoded.should eq(test_string)
      end
    end
  end
end
