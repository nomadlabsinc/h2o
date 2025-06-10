require "../spec_helper"
require "../../src/h2o"

describe "I/O Optimization Performance Comparison" do
  it "compares I/O batching performance" do
    puts "\n=== I/O Batching Performance Comparison ==="

    small_data = Bytes.new(1024) { |i| (i % 256).to_u8 }   # 1KB
    medium_data = Bytes.new(16384) { |i| (i % 256).to_u8 } # 16KB
    large_data = Bytes.new(65536) { |i| (i % 256).to_u8 }  # 64KB

    iterations = 10_000

    # Test 1: Baseline - Individual writes
    io1 = IO::Memory.new
    start_time = Time.monotonic

    iterations.times do |i|
      data = case i % 3
             when 0 then small_data
             when 1 then medium_data
             else        large_data
             end

      io1.write(data)
    end

    baseline_time = Time.monotonic - start_time
    baseline_bytes = io1.size

    # Test 2: Optimized - Batched writes
    io2 = IO::Memory.new
    batched_writer = H2O::IOOptimizer::BatchedWriter.new(io2, max_batch_size: 10)
    start_time = Time.monotonic

    iterations.times do |i|
      data = case i % 3
             when 0 then small_data
             when 1 then medium_data
             else        large_data
             end

      batched_writer.add(data)
    end
    batched_writer.flush

    optimized_time = Time.monotonic - start_time
    optimized_bytes = io2.size

    puts "Baseline (individual writes):"
    puts "  Total time: #{baseline_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{(baseline_bytes / baseline_time.total_seconds / 1024.0 / 1024.0).round(2)}MB/s"

    puts "\nOptimized (batched writes):"
    puts "  Total time: #{optimized_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{(optimized_bytes / optimized_time.total_seconds / 1024.0 / 1024.0).round(2)}MB/s"
    puts "  Batches flushed: #{batched_writer.stats.batches_flushed}"

    improvement = ((baseline_time - optimized_time) / baseline_time * 100).round(1)
    throughput_gain = ((optimized_bytes / optimized_time.total_seconds) / (baseline_bytes / baseline_time.total_seconds) - 1) * 100

    puts "\nImprovement:"
    puts "  Time reduction: #{improvement}%"
    puts "  Throughput gain: #{throughput_gain.round(1)}%"
    puts "  Syscall reduction: #{((iterations - batched_writer.stats.batches_flushed).to_f / iterations * 100).round(1)}%"
  end

  it "compares zero-copy frame parsing" do
    puts "\n=== Zero-Copy Frame Parsing Comparison ==="

    iterations = 100_000
    frame_header = Bytes.new(9)
    frame_header[0] = 0x00
    frame_header[1] = 0x00
    frame_header[2] = 0x0A
    frame_header[3] = 0x00
    frame_header[4] = 0x01
    frame_header[5] = 0x00
    frame_header[6] = 0x00
    frame_header[7] = 0x00
    frame_header[8] = 0x01

    # Test 1: Traditional parsing
    start_time = Time.monotonic

    iterations.times do
      io = IO::Memory.new(frame_header)

      length_bytes = Bytes.new(3)
      io.read_fully(length_bytes)
      length = (length_bytes[0].to_u32 << 16) | (length_bytes[1].to_u32 << 8) | length_bytes[2].to_u32

      type = io.read_byte.not_nil!
      flags = io.read_byte.not_nil!

      stream_id_bytes = Bytes.new(4)
      io.read_fully(stream_id_bytes)
      stream_id = ((stream_id_bytes[0].to_u32 << 24) |
                   (stream_id_bytes[1].to_u32 << 16) |
                   (stream_id_bytes[2].to_u32 << 8) |
                   stream_id_bytes[3].to_u32) & 0x7FFFFFFF
    end

    traditional_time = Time.monotonic - start_time

    # Test 2: Zero-copy parsing
    start_time = Time.monotonic

    iterations.times do
      # Direct byte access without intermediate allocations
      length = (frame_header[0].to_u32 << 16) |
               (frame_header[1].to_u32 << 8) |
               frame_header[2].to_u32

      type = frame_header[3]
      flags = frame_header[4]

      stream_id = ((frame_header[5].to_u32 << 24) |
                   (frame_header[6].to_u32 << 16) |
                   (frame_header[7].to_u32 << 8) |
                   frame_header[8].to_u32) & 0x7FFFFFFF
    end

    zerocopy_time = Time.monotonic - start_time

    puts "Traditional parsing:"
    puts "  Total time: #{traditional_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(traditional_time.total_nanoseconds / iterations).round(0)}ns"

    puts "\nZero-copy parsing:"
    puts "  Total time: #{zerocopy_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(zerocopy_time.total_nanoseconds / iterations).round(0)}ns"

    improvement = ((traditional_time - zerocopy_time) / traditional_time * 100).round(1)
    speedup = (traditional_time.total_nanoseconds / zerocopy_time.total_nanoseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end

  it "compares protocol-level optimizations" do
    puts "\n=== Protocol-Level Optimization Comparison ==="

    # Test window update batching
    iterations = 1000

    # Baseline: Individual window updates
    start_time = Time.monotonic
    updates_sent = 0

    iterations.times do |_i|
      consumed = Random.rand(1000..10000)
      if consumed >= 8192 # Threshold
        updates_sent += 1
      end
    end

    baseline_time = Time.monotonic - start_time

    # Optimized: Batched window updates
    window_optimizer = H2O::ProtocolOptimizer::WindowUpdateOptimizer.new
    start_time = Time.monotonic
    optimized_updates = 0

    iterations.times do |i|
      stream_id = (i % 10).to_u32 + 1
      consumed = Random.rand(1000..10000)
      window_optimizer.consume(stream_id, consumed)
    end

    updates = window_optimizer.get_updates
    optimized_updates = updates.size

    optimized_time = Time.monotonic - start_time

    puts "Window update optimization:"
    puts "  Baseline updates sent: #{updates_sent}"
    puts "  Optimized updates sent: #{optimized_updates}"
    puts "  Update reduction: #{((updates_sent - optimized_updates).to_f / updates_sent * 100).round(1)}%"

    # Test frame coalescing
    coalescer = H2O::ProtocolOptimizer::FrameCoalescer.new
    frames_added = 0
    coalesce_count = 0

    100.times do |i|
      # Create sample frames
      5.times do |_j|
        stream_id = (i % 10).to_u32 + 1
        frame = H2O::DataFrame.new(stream_id, Bytes.new(100), 0_u8)
        if coalescer.add(frame)
          frames_added += 1
        end
      end

      if coalesced = coalescer.get_coalesced
        coalesce_count += 1
      end
    end

    puts "\nFrame coalescing:"
    puts "  Frames added: #{frames_added}"
    puts "  Coalesce operations: #{coalesce_count}"
    puts "  Average frames per coalesce: #{frames_added.to_f / coalesce_count}"
  end

  it "measures real-world I/O optimization impact" do
    puts "\n=== Real-World I/O Optimization Impact ==="

    # Simulate HTTP/2 frame stream
    frame_sizes = [
      100,   # Small control frame
      1400,  # Typical data frame
      16384, # Large data frame
      50,    # Window update
      30,    # Settings ack
    ]

    iterations = 5000
    frames = Array(Bytes).new

    # Generate test frames
    iterations.times do |i|
      size = frame_sizes[i % frame_sizes.size]
      frames << Bytes.new(size) { |j| (j % 256).to_u8 }
    end

    # Test 1: Baseline - no optimization
    io1 = IO::Memory.new
    start_time = Time.monotonic

    frames.each do |frame|
      io1.write(frame)
    end

    baseline_time = Time.monotonic - start_time
    baseline_throughput = io1.size / baseline_time.total_seconds

    # Test 2: With I/O optimizations
    io2 = IO::Memory.new
    batched = H2O::IOOptimizer::BatchedWriter.new(io2)
    zero_writer = H2O::IOOptimizer::ZeroCopyWriter.new(io2)

    start_time = Time.monotonic

    frames.each do |frame|
      if frame.size < H2O::IOOptimizer::SMALL_BUFFER_SIZE
        batched.add(frame)
      else
        batched.flush
        zero_writer.write_from(frame)
      end
    end
    batched.flush

    optimized_time = Time.monotonic - start_time
    optimized_throughput = io2.size / optimized_time.total_seconds

    puts "Baseline performance:"
    puts "  Total time: #{baseline_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{(baseline_throughput / 1024.0 / 1024.0).round(2)}MB/s"

    puts "\nOptimized performance:"
    puts "  Total time: #{optimized_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{(optimized_throughput / 1024.0 / 1024.0).round(2)}MB/s"
    puts "  Batches: #{batched.stats.batches_flushed}"

    improvement = ((baseline_time - optimized_time) / baseline_time * 100).round(1)
    throughput_gain = ((optimized_throughput - baseline_throughput) / baseline_throughput * 100).round(1)

    puts "\nOverall improvement:"
    puts "  Time reduction: #{improvement}%"
    puts "  Throughput gain: #{throughput_gain}%"
    puts "  Write operations: #{frames.size} → #{batched.stats.write_operations + zero_writer.stats.write_operations}"
  end
end
