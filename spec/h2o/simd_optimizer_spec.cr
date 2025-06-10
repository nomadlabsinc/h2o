require "../spec_helper"

describe H2O::SIMDOptimizer do
  describe "FastFrameParser" do
    it "parses frame headers correctly" do
      # Create a test frame header
      header = Bytes.new(9)
      length = 0x001234_u32
      type = 0x01_u8
      flags = 0x05_u8
      stream_id = 0x12345678_u32

      H2O::SIMDOptimizer::FastFrameParser.write_header(header, length, type, flags, stream_id)
      parsed = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

      parsed[:length].should eq(length)
      parsed[:type].should eq(type)
      parsed[:flags].should eq(flags)
      parsed[:stream_id].should eq(stream_id & 0x7fffffff_u32) # Reserved bit cleared
    end

    it "handles reserved bit in stream ID correctly" do
      header = Bytes.new(9)
      stream_id_with_reserved = 0x87654321_u32 # Has reserved bit set

      H2O::SIMDOptimizer::FastFrameParser.write_header(header, 100_u32, 1_u8, 0_u8, stream_id_with_reserved)
      parsed = H2O::SIMDOptimizer::FastFrameParser.parse_header(header)

      parsed[:stream_id].should eq(0x07654321_u32) # Reserved bit cleared
    end

    it "parses headers in batch efficiently" do
      # Create multiple frame headers
      frame_count = 3
      header_data = Bytes.new(frame_count * 9)

      frame_count.times do |i|
        offset = i * 9
        header_slice = header_data[offset, 9]
        H2O::SIMDOptimizer::FastFrameParser.write_header(
          header_slice,
          (100 + i).to_u32,
          (i + 1).to_u8,
          0_u8,
          (i + 1).to_u32
        )
      end

      results = H2O::SIMDOptimizer::FastFrameParser.parse_headers_batch(header_data, frame_count)

      results.size.should eq(frame_count)
      results.each_with_index do |parsed, i|
        parsed[:length].should eq(100 + i)
        parsed[:type].should eq(i + 1)
        parsed[:stream_id].should eq(i + 1)
      end
    end

    it "handles partial batch data gracefully" do
      # Create incomplete header data
      partial_data = Bytes.new(15) # Only 1.5 headers worth of data

      results = H2O::SIMDOptimizer::FastFrameParser.parse_headers_batch(partial_data, 3)

      results.size.should eq(1) # Only one complete header
    end
  end

  describe "VectorOps" do
    it "compares bytes correctly with fast_equal" do
      a = "Hello World".to_slice
      b = "Hello World".to_slice
      c = "Hello Earth".to_slice

      H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_true
      H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, c).should be_false
    end

    it "handles different sized buffers in bytes_equal" do
      a = "Hello".to_slice
      b = "Hello World".to_slice

      H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_false
    end

    it "handles empty buffers in bytes_equal" do
      a = Bytes.empty
      b = Bytes.empty
      c = "test".to_slice

      H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, b).should be_true
      H2O::SIMDOptimizer::VectorOps.bytes_equal?(a, c).should be_false
    end

    it "performs fast memory copy correctly" do
      src = "Hello World Test Data".to_slice
      dst = Bytes.new(src.size)

      H2O::SIMDOptimizer::VectorOps.fast_copy(src, dst, src.size)

      String.new(dst).should eq("Hello World Test Data")
    end

    it "handles small buffer copy" do
      src = "Hello".to_slice
      dst = Bytes.new(src.size)

      H2O::SIMDOptimizer::VectorOps.fast_copy(src, dst, src.size)

      String.new(dst).should eq("Hello")
    end

    it "zeros buffer efficiently" do
      buffer = Bytes.new(64, 0xff_u8) # Fill with 0xFF

      H2O::SIMDOptimizer::VectorOps.fast_zero(buffer)

      buffer.all? { |byte| byte == 0_u8 }.should be_true
    end

    it "calculates checksums consistently" do
      data1 = "Hello World".to_slice
      data2 = "Hello World".to_slice
      data3 = "Different Data".to_slice

      checksum1 = H2O::SIMDOptimizer::VectorOps.fast_checksum(data1)
      checksum2 = H2O::SIMDOptimizer::VectorOps.fast_checksum(data2)
      checksum3 = H2O::SIMDOptimizer::VectorOps.fast_checksum(data3)

      checksum1.should eq(checksum2)
      checksum1.should_not eq(checksum3)
    end

    it "handles empty data in checksum" do
      empty_data = Bytes.empty
      checksum = H2O::SIMDOptimizer::VectorOps.fast_checksum(empty_data)

      checksum.should eq(0_u32)
    end
  end

  describe "HPACKOptimizer" do
    it "encodes varints efficiently" do
      # Test single-byte varint
      encoded = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(127)
      encoded.should eq(Bytes[127])

      # Test multi-byte varint
      encoded = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(1337)
      encoded.size.should be > 1
    end

    it "decodes varints correctly" do
      # Test single-byte
      result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(Bytes[100], 0)
      result[:value].should eq(100)
      result[:bytes_consumed].should eq(1)

      # Test multi-byte
      encoded = H2O::SIMDOptimizer::HPACKOptimizer.encode_varint_fast(1337)
      result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(encoded, 0)
      result[:value].should eq(1337)
      result[:bytes_consumed].should eq(encoded.size)
    end

    it "handles varint edge cases" do
      # Empty buffer
      result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(Bytes.empty, 0)
      result[:value].should eq(0)
      result[:bytes_consumed].should eq(0)

      # Out of bounds offset
      result = H2O::SIMDOptimizer::HPACKOptimizer.decode_varint_fast(Bytes[1, 2, 3], 5)
      result[:value].should eq(0)
      result[:bytes_consumed].should eq(0)
    end

    it "detects huffman encoding candidates correctly" do
      # Short data - should not encode
      short_data = "Hi".to_slice
      H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(short_data).should be_false

      # Random data with low uniqueness - should encode (use non-base64-like pattern)
      repeated_data = ("hello world " * 10).to_slice
      H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(repeated_data).should be_true

      # High ASCII content - should encode
      ascii_data = "This is a long ASCII string with many repeated patterns and words".to_slice
      H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(ascii_data).should be_true

      # Already encoded data (base64-like) - should not encode
      encoded_data = "YWJjZGVmZ2hpamtsbW5vcA==".to_slice
      H2O::SIMDOptimizer::HPACKOptimizer.should_huffman_encode?(encoded_data).should be_false
    end
  end

  describe "Validator" do
    it "validates frame sizes correctly" do
      # Valid DATA frame
      H2O::SIMDOptimizer::Validator.validate_frame_size(1000_u32, 0x0_u8).should be_true

      # Valid PRIORITY frame
      H2O::SIMDOptimizer::Validator.validate_frame_size(5_u32, 0x2_u8).should be_true

      # Invalid PRIORITY frame (wrong size)
      H2O::SIMDOptimizer::Validator.validate_frame_size(4_u32, 0x2_u8).should be_false

      # Valid PING frame
      H2O::SIMDOptimizer::Validator.validate_frame_size(8_u32, 0x6_u8).should be_true

      # Invalid PING frame (wrong size)
      H2O::SIMDOptimizer::Validator.validate_frame_size(10_u32, 0x6_u8).should be_false

      # Valid SETTINGS frame (multiple of 6)
      H2O::SIMDOptimizer::Validator.validate_frame_size(12_u32, 0x4_u8).should be_true

      # Invalid SETTINGS frame (not multiple of 6)
      H2O::SIMDOptimizer::Validator.validate_frame_size(13_u32, 0x4_u8).should be_false

      # Unknown frame type
      H2O::SIMDOptimizer::Validator.validate_frame_size(100_u32, 0xFF_u8).should be_false
    end

    it "validates frames in batch" do
      headers = [
        {length: 1000_u32, type: 0x0_u8, flags: 0_u8, stream_id: 1_u32}, # Valid DATA
        {length: 5_u32, type: 0x2_u8, flags: 0_u8, stream_id: 1_u32},    # Valid PRIORITY
        {length: 10_u32, type: 0x6_u8, flags: 0_u8, stream_id: 0_u32},   # Invalid PING size
        {length: 8_u32, type: 0x6_u8, flags: 0_u8, stream_id: 0_u32},    # Valid PING
      ]

      results = H2O::SIMDOptimizer::Validator.validate_frames_batch(headers)

      results.should eq([true, true, false, true])
    end
  end

  describe "PerformanceMonitor" do
    it "tracks performance metrics correctly" do
      monitor = H2O::SIMDOptimizer::PerformanceMonitor.new

      # Record some operations
      monitor.record_operation(1000, 1.millisecond)
      monitor.record_operation(2000, 2.milliseconds)

      monitor.operations_count.should eq(2)
      monitor.total_bytes_processed.should eq(3000)
      monitor.total_time.should eq(3.milliseconds)

      # Check calculated metrics
      monitor.throughput_mbps.should be > 0.0
      monitor.average_operation_time.should eq(1.5.milliseconds)
      monitor.operations_per_second.should be > 0.0
    end

    it "handles zero operations gracefully" do
      monitor = H2O::SIMDOptimizer::PerformanceMonitor.new

      monitor.throughput_mbps.should eq(0.0)
      monitor.average_operation_time.should eq(Time::Span.zero)
      monitor.operations_per_second.should eq(0.0)
    end
  end

  describe "Integration with FrameBatchProcessor" do
    it "integrates SIMD optimizations in frame processing" do
      processor = H2O::FrameBatchProcessor.new

      # Create test frame data
      frame_data = IO::Memory.new

      # Write a simple DATA frame header
      header = Bytes.new(9)
      H2O::SIMDOptimizer::FastFrameParser.write_header(header, 5_u32, 0x0_u8, 0x1_u8, 1_u32)
      frame_data.write(header)
      frame_data.write("Hello".to_slice) # Payload

      frame_data.rewind

      # Process the frame
      frames = processor.read_batch(frame_data)

      frames.size.should eq(1)
      frames[0].frame_type.should eq(H2O::FrameType::Data)
      frames[0].length.should eq(5)
      frames[0].flags.should eq(1)
      frames[0].stream_id.should eq(1)
    end
  end
end
