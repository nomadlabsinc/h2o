require "../spec_helper"
require "../../src/h2o"

describe "I/O Optimization Integration" do
  it "tests protocol optimization components directly" do
    puts "\n=== Protocol Optimization Component Tests ==="

    # Test window update optimization
    window_opt = H2O::ProtocolOptimizer::WindowUpdateOptimizer.new

    # Simulate data consumption pattern
    100.times do |i|
      stream_id = (i % 5).to_u32 + 1
      bytes = Random.rand(1000..15000)
      window_opt.consume(stream_id, bytes)
    end

    updates = window_opt.get_updates
    puts "Window update batching:"
    puts "  Streams tracked: 5"
    puts "  Updates generated: #{updates.size}"
    puts "  Total bytes to update: #{updates.sum(&.increment)}"

    # Verify batching works
    updates.size.should be <= 6 # Max 5 streams + 1 connection

    # Test frame coalescing
    coalescer = H2O::ProtocolOptimizer::FrameCoalescer.new
    frames_added = 0
    coalesce_count = 0

    # Add frames in bursts
    10.times do |burst|
      5.times do |i|
        frame = H2O::DataFrame.new((i + 1).to_u32, Bytes.new(1000), 0_u8)
        if coalescer.add(frame)
          frames_added += 1
        end
      end

      if coalesced = coalescer.get_coalesced
        coalesce_count += 1
        puts "\nCoalesced burst #{burst + 1}: #{coalesced.size} frames"
        coalesced.size.should be >= 3 # Should meet threshold
      end
    end

    puts "\nTotal coalescing stats:"
    puts "  Frames added: #{frames_added}"
    puts "  Coalesce operations: #{coalesce_count}"

    # Test priority optimization
    priority_opt = H2O::ProtocolOptimizer::PriorityOptimizer.new

    # Set priorities based on content type
    priority_opt.optimize_by_content_type(1_u32, "text/html")
    priority_opt.optimize_by_content_type(2_u32, "application/json")
    priority_opt.optimize_by_content_type(3_u32, "image/png")
    priority_opt.optimize_by_content_type(4_u32, "text/css")

    # Get optimized order
    streams = [1_u32, 2_u32, 3_u32, 4_u32]
    optimized_order = priority_opt.get_write_order(streams)

    puts "\nPriority optimization:"
    puts "  Original order: #{streams}"
    puts "  Optimized order: #{optimized_order}"

    # High priority should come first
    optimized_order[0..1].should contain(1_u32)
    optimized_order[0..1].should contain(2_u32)
    optimized_order.last.should eq(3_u32) # Images should be last

    # Test state caching
    state_opt = H2O::ProtocolOptimizer::StateOptimizer.new

    # Cache some protocol support
    state_opt.cache_http2_support("example.com", true)
    state_opt.cache_http2_support("legacy.com", false)
    state_opt.cache_alpn_protocol("secure.com", "h2")

    # Verify caching works
    state_opt.http2_supported?("example.com").should eq(true)
    state_opt.http2_supported?("legacy.com").should eq(false)
    state_opt.http2_supported?("unknown.com").should be_nil
    state_opt.cached_alpn_protocol("secure.com").should eq("h2")

    puts "\nState caching:"
    puts "  HTTP/2 support cached correctly"
    puts "  ALPN protocol cached correctly"
  end

  it "tests I/O optimization statistics" do
    puts "\n=== I/O Optimization Statistics Test ==="

    # Create test I/O
    io = IO::Memory.new

    # Test batched writer
    writer = H2O::IOOptimizer::BatchedWriter.new(io, max_batch_size: 5)

    # Add various sized data
    small_data = Bytes.new(100) { |i| (i % 256).to_u8 }
    medium_data = Bytes.new(1000) { |i| (i % 256).to_u8 }

    10.times do |i|
      data = i.even? ? small_data : medium_data
      writer.add(data)
    end
    writer.flush

    stats = writer.stats
    puts "Batched writer statistics:"
    puts "  Bytes written: #{stats.bytes_written}"
    puts "  Write operations: #{stats.write_operations}"
    puts "  Batches flushed: #{stats.batches_flushed}"
    puts "  Average write size: #{stats.average_write_size.round(0)} bytes"

    # Verify batching worked
    stats.write_operations.should be < 10
    stats.batches_flushed.should be >= 2
    stats.bytes_written.should eq(5500) # 5 * 100 + 5 * 1000

    # Test zero-copy operations
    io2 = IO::Memory.new
    zero_writer = H2O::IOOptimizer::ZeroCopyWriter.new(io2)

    # Write multiple buffers
    buffers = [small_data, medium_data, small_data]
    zero_writer.write_buffers(buffers)

    zstats = zero_writer.stats
    puts "\nZero-copy writer statistics:"
    puts "  Bytes written: #{zstats.bytes_written}"
    puts "  Write operations: #{zstats.write_operations}"
    puts "  Write throughput: #{(zstats.write_throughput / 1024.0 / 1024.0).round(2)}MB/s"

    zstats.bytes_written.should eq(1200) # 100 + 1000 + 100
    zstats.write_operations.should eq(1) # Single batched write
  end

  it "tests optimized settings for different scenarios" do
    puts "\n=== Optimized Settings Test ==="

    # Test high throughput settings
    high_tp = H2O::ProtocolOptimizer::SettingsOptimizer.high_throughput_settings
    puts "High throughput settings:"
    puts "  Window size: #{high_tp[H2O::SettingIdentifier::InitialWindowSize]} bytes"
    puts "  Max concurrent streams: #{high_tp[H2O::SettingIdentifier::MaxConcurrentStreams]}"
    puts "  Max frame size: #{high_tp[H2O::SettingIdentifier::MaxFrameSize]} bytes"

    # Verify settings are optimized for throughput
    high_tp[H2O::SettingIdentifier::InitialWindowSize].should be >= 1_048_576
    high_tp[H2O::SettingIdentifier::MaxConcurrentStreams].should be >= 1000

    # Test low latency settings
    low_lat = H2O::ProtocolOptimizer::SettingsOptimizer.low_latency_settings
    puts "\nLow latency settings:"
    puts "  Window size: #{low_lat[H2O::SettingIdentifier::InitialWindowSize]} bytes"
    puts "  Max concurrent streams: #{low_lat[H2O::SettingIdentifier::MaxConcurrentStreams]}"
    puts "  Max frame size: #{low_lat[H2O::SettingIdentifier::MaxFrameSize]} bytes"

    # Verify settings are optimized for latency
    low_lat[H2O::SettingIdentifier::MaxFrameSize].should be <= 16_384
    low_lat[H2O::SettingIdentifier::MaxConcurrentStreams].should be <= 100

    # Test balanced settings
    balanced = H2O::ProtocolOptimizer::SettingsOptimizer.balanced_settings
    puts "\nBalanced settings:"
    puts "  Window size: #{balanced[H2O::SettingIdentifier::InitialWindowSize]} bytes"
    puts "  Max concurrent streams: #{balanced[H2O::SettingIdentifier::MaxConcurrentStreams]}"

    # Verify balanced settings are in between
    balanced[H2O::SettingIdentifier::InitialWindowSize].should be > low_lat[H2O::SettingIdentifier::InitialWindowSize]
    balanced[H2O::SettingIdentifier::InitialWindowSize].should be < high_tp[H2O::SettingIdentifier::InitialWindowSize]
  end
end
