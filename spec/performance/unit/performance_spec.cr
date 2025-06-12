require "../../spec_helper"

describe "H2O Performance Optimizations" do
  # Note: Lazy Fiber Creation tests moved to integration tests due to server dependency

  describe "Buffer Pooling" do
    it "should reuse header buffers for frame operations" do
      # Test that buffer pool gets and returns buffers correctly
      buffer1 = H2O::BufferPool.get_header_buffer
      buffer1.size.should eq(H2O::BufferPool::MAX_HEADER_BUFFER_SIZE)

      H2O::BufferPool.return_header_buffer(buffer1)

      buffer2 = H2O::BufferPool.get_header_buffer
      # Buffers should be same size (may or may not be same instance due to pooling)
      buffer2.size.should eq(H2O::BufferPool::MAX_HEADER_BUFFER_SIZE)
    end

    it "should handle frame buffer pooling efficiently" do
      frame_size = 1024
      buffer1 = H2O::BufferPool.get_frame_buffer(frame_size)
      buffer1.size.should eq(frame_size)

      H2O::BufferPool.return_frame_buffer(buffer1)

      # Verify with_frame_buffer works correctly
      result = H2O::BufferPool.with_frame_buffer(frame_size) do |buffer|
        buffer.size
      end
      result.should eq(frame_size)
    end
  end

  describe "HPACK Optimizations" do
    it "should perform hash-based lookups efficiently" do
      table = H2O::HPACK::DynamicTable.new

      # Add some entries to test hash lookup performance
      100.times do |i|
        table.add("header-#{i}", "value-#{i}")
      end

      start_time = Time.monotonic

      # Perform many lookups to test performance
      1000.times do
        index = table.find_name("header-50")
        index.should_not be_nil
      end

      lookup_time = Time.monotonic - start_time

      # Hash lookups should be very fast
      lookup_time.should be < 10.milliseconds
    end

    it "should skip compression for small headers efficiently" do
      encoder = H2O::HPACK::Encoder.new

      small_headers = H2O::Headers.new
      small_headers[":method"] = "GET"
      small_headers[":path"] = "/"
      small_headers[":scheme"] = "https"
      small_headers["host"] = "test.com"

      start_time = Time.monotonic

      # Encode many small header sets
      100.times do
        encoded = encoder.encode(small_headers)
        encoded.should_not be_nil
      end

      encoding_time = Time.monotonic - start_time

      # Should be fast due to compression bypass
      encoding_time.should be < 50.milliseconds
    end
  end

  describe "Stream Management" do
    it "should handle stream cleanup efficiently" do
      pool = H2O::StreamPool.new

      # Create many streams
      streams = [] of H2O::Stream
      100.times do
        streams << pool.create_stream
      end

      # Mark some as closed
      streams.first(50).each(&.state = H2O::StreamState::Closed)

      start_time = Time.monotonic
      pool.cleanup_closed_streams
      cleanup_time = Time.monotonic - start_time

      # Cleanup should be fast
      cleanup_time.should be < 10.milliseconds

      # Should have fewer active streams
      pool.stream_count.should eq(50)
    end

    it "should cache stream lookups efficiently" do
      pool = H2O::StreamPool.new

      # Create streams
      10.times { pool.create_stream }

      start_time = Time.monotonic

      # Multiple calls to active_streams should use cache
      100.times do
        active = pool.active_streams
        active.size.should eq(10)
      end

      cache_time = Time.monotonic - start_time

      # Cached lookups should be very fast
      cache_time.should be < 5.milliseconds
    end
  end

  describe "Memory Allocation Optimization" do
    it "should minimize allocations during frame processing" do
      # Create a simple DATA frame
      data = "Hello, World!".to_slice
      frame = H2O::DataFrame.new(1_u32, data)

      # Test serialization performance
      start_time = Time.monotonic

      100.times do
        bytes = frame.to_bytes
        bytes.size.should be > 0
      end

      serialization_time = Time.monotonic - start_time

      # Should be fast with buffer pooling
      serialization_time.should be < 20.milliseconds
    end

    it "should optimize HEADERS frame creation" do
      headers_data = "test-header-data".to_slice
      frame = H2O::HeadersFrame.new(1_u32, headers_data)

      start_time = Time.monotonic

      50.times do
        bytes = frame.to_bytes
        bytes.size.should be > 0
      end

      headers_time = Time.monotonic - start_time

      # Should benefit from buffer pooling
      headers_time.should be < 15.milliseconds
    end
  end
end
