require "../spec_helper"

describe H2O::SIMDOptimizer do
  describe H2O::SIMDOptimizer::FastFrameParser do
    describe ".parse_header" do
      it "correctly parses HTTP/2 frame header" do
        # Example: DATA frame with length=256, type=0, flags=1, stream_id=1
        header = Bytes[
          0x00, 0x01, 0x00,      # length: 256 (24-bit)
          0x00,                  # type: DATA
          0x01,                  # flags: END_STREAM
          0x00, 0x00, 0x00, 0x01 # stream_id: 1 (31-bit, reserved bit cleared)
        ]

        result = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

        result[:length].should eq(256_u32)
        result[:type].should eq(0_u8)
        result[:flags].should eq(1_u8)
        result[:stream_id].should eq(1_u32)
      end

      it "handles maximum frame length" do
        # Max frame size: 16777215 (2^24 - 1)
        header = Bytes[
          0xff, 0xff, 0xff,      # length: 16777215
          0x01,                  # type: HEADERS
          0x04,                  # flags: END_HEADERS
          0x00, 0x00, 0x00, 0x10 # stream_id: 16
        ]

        result = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

        result[:length].should eq(16777215_u32)
        result[:type].should eq(1_u8)
        result[:flags].should eq(4_u8)
        result[:stream_id].should eq(16_u32)
      end

      it "clears reserved bit from stream ID" do
        # Stream ID with reserved bit set
        header = Bytes[
          0x00, 0x00, 0x0a,      # length: 10
          0x02,                  # type: PRIORITY
          0x00,                  # flags: none
          0x80, 0x00, 0x00, 0x01 # stream_id: 1 with reserved bit set
        ]

        result = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

        result[:stream_id].should eq(1_u32) # Reserved bit should be cleared
      end

      it "handles zero values" do
        header = Bytes[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

        result = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

        result[:length].should eq(0_u32)
        result[:type].should eq(0_u8)
        result[:flags].should eq(0_u8)
        result[:stream_id].should eq(0_u32)
      end
    end

    describe ".write_header" do
      it "correctly writes HTTP/2 frame header" do
        header = Bytes.new(9)

        H2O::SIMDOptimizer::FastFrameParser.write_header(
          header, 1024_u32, 1_u8, 5_u8, 42_u32
        )

        # Verify the written bytes
        header[0].should eq(0x00) # length high byte
        header[1].should eq(0x04) # length middle byte
        header[2].should eq(0x00) # length low byte
        header[3].should eq(1)    # type
        header[4].should eq(5)    # flags
        header[5].should eq(0x00) # stream_id high byte
        header[6].should eq(0x00) # stream_id
        header[7].should eq(0x00) # stream_id
        header[8].should eq(42)   # stream_id low byte
      end

      it "round-trips with parse_header" do
        original_length = 2048_u32
        original_type = 3_u8
        original_flags = 7_u8
        original_stream_id = 123_u32

        header = Bytes.new(9)
        H2O::SIMDOptimizer::FastFrameParser.write_header(
          header, original_length, original_type, original_flags, original_stream_id
        )

        result = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

        result[:length].should eq(original_length)
        result[:type].should eq(original_type)
        result[:flags].should eq(original_flags)
        result[:stream_id].should eq(original_stream_id)
      end
    end

    describe ".parse_headers_batch" do
      it "parses multiple frame headers" do
        # Create data with 3 frame headers
        data = Bytes[
          # Frame 1: length=100, type=0, flags=1, stream_id=1
          0x00, 0x00, 0x64, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          # Frame 2: length=200, type=1, flags=4, stream_id=3
          0x00, 0x00, 0xc8, 0x01, 0x04, 0x00, 0x00, 0x00, 0x03,
          # Frame 3: length=50, type=2, flags=0, stream_id=5
          0x00, 0x00, 0x32, 0x02, 0x00, 0x00, 0x00, 0x00, 0x05,
        ]

        results = H2O::SIMDOptimizer::FastFrameParser.parse_headers_batch(data, 3)

        results.size.should eq(3)

        results[0][:length].should eq(100_u32)
        results[0][:type].should eq(0_u8)
        results[0][:stream_id].should eq(1_u32)

        results[1][:length].should eq(200_u32)
        results[1][:type].should eq(1_u8)
        results[1][:stream_id].should eq(3_u32)

        results[2][:length].should eq(50_u32)
        results[2][:type].should eq(2_u8)
        results[2][:stream_id].should eq(5_u32)
      end

      it "handles incomplete data gracefully" do
        # Only enough data for 1 complete header
        data = Bytes[0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]

        results = H2O::SIMDOptimizer::FastFrameParser.parse_headers_batch(data, 3)

        results.size.should eq(1)
        results[0][:length].should eq(10_u32)
        results[0][:stream_id].should eq(1_u32)
      end
    end
  end

  describe H2O::SIMDOptimizer::VectorOps do
    describe ".bytes_equal?" do
      it "returns true for identical byte arrays" do
        a = Bytes[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        b = Bytes[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_true
      end

      it "returns false for different byte arrays" do
        a = Bytes[1, 2, 3, 4, 5, 6, 7, 8]
        b = Bytes[1, 2, 3, 4, 5, 6, 7, 9]

        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_false
      end

      it "returns false for different sized arrays" do
        a = Bytes[1, 2, 3, 4]
        b = Bytes[1, 2, 3, 4, 5]

        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_false
      end

      it "returns true for empty arrays" do
        a = Bytes.empty
        b = Bytes.empty

        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_true
      end

      it "handles large arrays efficiently" do
        # Test with arrays larger than 64 bytes to test word-aligned processing
        a = Bytes.new(128, &.to_u8)
        b = Bytes.new(128, &.to_u8)

        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_true

        # Modify one byte
        b[100] = 255_u8
        H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_false
      end
    end

    describe ".fast_copy" do
      it "copies small byte arrays correctly" do
        src = Bytes[1, 2, 3, 4, 5]
        dst = Bytes.new(5)

        H2O::SIMDOptimizer::VectorOps.fast_copy(src, dst, 5)

        dst.should eq(src)
      end

      it "copies large byte arrays correctly" do
        src = Bytes.new(100) { |i| (i % 256).to_u8 }
        dst = Bytes.new(100)

        H2O::SIMDOptimizer::VectorOps.fast_copy(src, dst, 100)

        dst.should eq(src)
      end

      it "handles edge case sizes" do
        # Test boundary conditions around 8-byte word alignment
        [1, 7, 8, 9, 15, 16, 17, 31, 32, 33].each do |size|
          src = Bytes.new(size, &.to_u8)
          dst = Bytes.new(size)

          H2O::SIMDOptimizer::VectorOps.fast_copy(src, dst, size)

          dst.should eq(src)
        end
      end
    end

    describe ".fast_zero" do
      it "zeros small buffers" do
        buffer = Bytes[1, 2, 3, 4, 5]

        H2O::SIMDOptimizer::VectorOps.fast_zero(buffer)

        buffer.all?(&.zero?).should be_true
      end

      it "zeros large buffers" do
        buffer = Bytes.new(100, 255_u8) # Initialize with non-zero values

        H2O::SIMDOptimizer::VectorOps.fast_zero(buffer)

        buffer.all?(&.zero?).should be_true
      end

      it "handles various buffer sizes" do
        [1, 7, 8, 9, 15, 16, 17, 63, 64, 65].each do |size|
          buffer = Bytes.new(size, 255_u8)

          H2O::SIMDOptimizer::VectorOps.fast_zero(buffer)

          buffer.all?(&.zero?).should be_true
        end
      end
    end

    describe ".fast_checksum" do
      it "calculates checksum for small data" do
        data = Bytes[1, 2, 3, 4]

        checksum = H2O::SIMDOptimizer::VectorOps.fast_checksum(data)

        # Verify the checksum calculation
        expected = 1_u32 + (2_u32 << 8) + (3_u32 << 16) + (4_u32 << 24)
        checksum.should eq(expected)
      end

      it "calculates checksum for large data" do
        data = Bytes.new(100) { |i| (i % 256).to_u8 }

        checksum = H2O::SIMDOptimizer::VectorOps.fast_checksum(data)

        # Should return a valid checksum without crashing
        checksum.should be_a(UInt32)
      end

      it "returns zero for empty data" do
        data = Bytes.empty

        checksum = H2O::SIMDOptimizer::VectorOps.fast_checksum(data)

        checksum.should eq(0_u32)
      end

      it "handles non-4-byte-aligned data" do
        [1, 2, 3, 5, 6, 7, 9, 10, 11].each do |size|
          data = Bytes.new(size) { |i| (i + 1).to_u8 }

          checksum = H2O::SIMDOptimizer::VectorOps.fast_checksum(data)

          # Should return a valid checksum
          checksum.should be_a(UInt32)
        end
      end
    end
  end

  describe H2O::SIMDOptimizer::HPACKOptimizer do
    describe ".encode_varint_fast" do
      it "encodes single-byte values" do
        result = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(127)

        result.size.should eq(1)
        result[0].should eq(127_u8)
      end

      it "encodes two-byte values" do
        result = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(255)

        result.size.should eq(2)
        result[0].should eq(0xff_u8) # 127 with continuation bit
        result[1].should eq(0x01_u8) # Remaining value
      end

      it "encodes larger values" do
        result = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(16383)

        result.size.should eq(2)
        # Verify the varint encoding
        decoded = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(result, 0)
        decoded[:value].should eq(16383)
      end
    end

    describe ".decode_varint_fast" do
      it "decodes single-byte values" do
        data = Bytes[42]

        result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(data, 0)

        result[:value].should eq(42)
        result[:bytes_consumed].should eq(1)
      end

      it "decodes multi-byte values" do
        data = Bytes[0x80 | 10, 0x02] # Varint for 266

        result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(data, 0)

        result[:value].should eq(266)
        result[:bytes_consumed].should eq(2)
      end

      it "handles empty data" do
        data = Bytes.empty

        result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(data, 0)

        result[:value].should eq(0)
        result[:bytes_consumed].should eq(0)
      end

      it "round-trips with encode_varint_fast" do
        [0, 1, 127, 128, 255, 16383, 16384, 65535].each do |value|
          encoded = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(value)
          decoded = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(encoded, 0)

          decoded[:value].should eq(value)
          decoded[:bytes_consumed].should eq(encoded.size)
        end
      end
    end

    describe ".should_huffman_encode?" do
      it "returns false for small data" do
        data = Bytes[1, 2, 3]

        H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(data).should be_false
      end

      it "returns false for base64-like data" do
        # Typical base64 string
        data = "YWJjZGVmZ2hpamtsbW5vcA==".to_slice

        H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(data).should be_false
      end

      it "returns true for repetitive text" do
        # Use text that meets the compression criteria: low uniqueness + high ASCII ratio
        data = "hello world hello world hello world hello world hello world".to_slice

        H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(data).should be_true
      end

      it "returns true for high ASCII content" do
        # Normal text should compress well
        data = "this is normal text with spaces and punctuation.".to_slice

        H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(data).should be_true
      end
    end
  end

  describe H2O::SIMDOptimizer::Validator do
    describe ".validate_frame_size" do
      it "validates DATA frame sizes" do
        H2O::SIMDOptimizer::Validator.validate_frame_size(1024_u32, 0x0_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(16777216_u32, 0x0_u8).should be_false
      end

      it "validates PRIORITY frame size" do
        H2O::SIMDOptimizer::Validator.validate_frame_size(5_u32, 0x2_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(4_u32, 0x2_u8).should be_false
        H2O::SIMDOptimizer::Validator.validate_frame_size(6_u32, 0x2_u8).should be_false
      end

      it "validates PING frame size" do
        H2O::SIMDOptimizer::Validator.validate_frame_size(8_u32, 0x6_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(7_u32, 0x6_u8).should be_false
        H2O::SIMDOptimizer::Validator.validate_frame_size(9_u32, 0x6_u8).should be_false
      end

      it "validates SETTINGS frame size" do
        H2O::SIMDOptimizer::Validator.validate_frame_size(0_u32, 0x4_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(6_u32, 0x4_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(12_u32, 0x4_u8).should be_true
        H2O::SIMDOptimizer::Validator.validate_frame_size(5_u32, 0x4_u8).should be_false
        H2O::SIMDOptimizer::Validator.validate_frame_size(1030_u32, 0x4_u8).should be_false
      end

      it "rejects unknown frame types" do
        H2O::SIMDOptimizer::Validator.validate_frame_size(100_u32, 0xFF_u8).should be_false
      end
    end

    describe ".validate_frames_batch" do
      it "validates multiple frames" do
        headers = [
          {length: 5_u32, type: 0x2_u8, flags: 0_u8, stream_id: 1_u32},    # PRIORITY: valid
          {length: 8_u32, type: 0x6_u8, flags: 0_u8, stream_id: 0_u32},    # PING: valid
          {length: 10_u32, type: 0x2_u8, flags: 0_u8, stream_id: 3_u32},   # PRIORITY: invalid
          {length: 1000_u32, type: 0x0_u8, flags: 0_u8, stream_id: 5_u32}, # DATA: valid
        ]

        results = H2O::SIMDOptimizer::Validator.validate_frames_batch(headers)

        results.should eq([true, true, false, true])
      end
    end
  end

  describe H2O::SIMDOptimizer::PerformanceMonitor do
    it "tracks operation statistics" do
      monitor = H2O::SIMDOptimizer::PerformanceMonitor.new

      monitor.operations_count.should eq(0)
      monitor.total_bytes_processed.should eq(0)

      # Record some operations
      monitor.record_operation(1024, 100.microseconds)
      monitor.record_operation(2048, 200.microseconds)

      monitor.operations_count.should eq(2)
      monitor.total_bytes_processed.should eq(3072)
      monitor.total_time.should eq(300.microseconds)
    end

    it "calculates throughput metrics" do
      monitor = H2O::SIMDOptimizer::PerformanceMonitor.new

      # 1MB in 1 second
      monitor.record_operation(1024 * 1024, 1.second)

      monitor.throughput_mbps.should be_close(1.0, 0.1)
      monitor.operations_per_second.should be_close(1.0, 0.1)
      monitor.average_operation_time.should eq(1.second)
    end

    it "handles zero time gracefully" do
      monitor = H2O::SIMDOptimizer::PerformanceMonitor.new

      monitor.throughput_mbps.should eq(0.0)
      monitor.operations_per_second.should eq(0.0)
      monitor.average_operation_time.should eq(Time::Span.zero)
    end
  end
end
