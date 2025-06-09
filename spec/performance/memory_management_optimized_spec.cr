require "../spec_helper"
require "../../src/h2o"

describe "Memory Management Optimization - Performance Comparison" do
  it "compares object allocation with and without pooling" do
    puts "\n=== Object Pooling Performance Comparison ==="

    iterations = 100_000

    # Test 1: Without pooling (baseline)
    start_time = Time.monotonic
    streams_without_pool = Array(H2O::Stream).new

    iterations.times do |i|
      stream = H2O::Stream.new((i % 1000).to_u32 + 1)
      streams_without_pool << stream if i < 100
    end

    time_without_pool = Time.monotonic - start_time

    # Test 2: With pooling
    stream_pool = H2O::StreamObjectPool.new(1000)
    start_time = Time.monotonic
    streams_with_pool = Array(H2O::Stream).new

    iterations.times do |i|
      stream = stream_pool.acquire((i % 1000).to_u32 + 1)
      if i < 100
        streams_with_pool << stream
      else
        # Simulate release back to pool
        stream_pool.release(stream)
      end
    end

    time_with_pool = Time.monotonic - start_time

    puts "Without pooling:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_without_pool.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_without_pool.total_microseconds / iterations).round(2)}μs"
    puts "  Objects per second: #{(iterations / time_without_pool.total_seconds).round(0)}"

    puts "\nWith pooling:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_with_pool.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_with_pool.total_microseconds / iterations).round(2)}μs"
    puts "  Objects per second: #{(iterations / time_with_pool.total_seconds).round(0)}"
    puts "  Pool efficiency: #{stream_pool.pool.size} objects in pool"

    improvement = ((time_without_pool - time_with_pool) / time_without_pool * 100).round(1)
    speedup = (time_without_pool.total_milliseconds / time_with_pool.total_milliseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"

    # Cleanup
    streams_with_pool.each { |stream| stream_pool.release(stream) }
  end

  it "compares string allocation with and without interning" do
    puts "\n=== String Interning Performance Comparison ==="

    common_headers = [
      "content-type", "content-length", "accept", "accept-encoding",
      "user-agent", "host", "connection", "cache-control",
    ]

    iterations = 100_000

    # Test 1: Without interning
    start_time = Time.monotonic
    headers_without_intern = Array(String).new
    total_bytes_without = 0_i64

    iterations.times do |i|
      header = common_headers[i % common_headers.size]
      # Simulate string duplication
      new_header = header.dup
      headers_without_intern << new_header if i < 1000
      total_bytes_without += new_header.bytesize
    end

    time_without_intern = Time.monotonic - start_time

    # Test 2: With interning
    string_pool = H2O::StringPool.new
    start_time = Time.monotonic
    headers_with_intern = Array(String).new
    total_bytes_with = 0_i64

    iterations.times do |i|
      header = common_headers[i % common_headers.size]
      # Use interned string
      interned_header = string_pool.intern(header)
      headers_with_intern << interned_header if i < 1000
      total_bytes_with += interned_header.bytesize
    end

    time_with_intern = Time.monotonic - start_time
    stats = string_pool.statistics

    puts "Without interning:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_without_intern.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_without_intern.total_microseconds / iterations).round(3)}μs"
    puts "  Total bytes allocated: #{total_bytes_without}"

    puts "\nWith interning:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_with_intern.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_with_intern.total_microseconds / iterations).round(3)}μs"
    puts "  Pool size: #{string_pool.size} strings"
    puts "  Cache hits: #{stats.hits}"
    puts "  Cache misses: #{stats.misses}"
    puts "  Hit rate: #{(stats.hit_rate * 100).round(1)}%"
    puts "  Bytes saved: #{stats.bytes_saved}"

    improvement = ((time_without_intern - time_with_intern) / time_without_intern * 100).round(1)
    memory_savings = ((stats.bytes_saved.to_f / total_bytes_without) * 100).round(1)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Memory savings: #{memory_savings}%"
  end

  it "measures frame pooling performance" do
    puts "\n=== Frame Object Pooling Performance ==="

    iterations = 50_000

    # Test 1: Without pooling
    start_time = Time.monotonic
    gc_start = GC.stats.total_bytes

    iterations.times do |i|
      stream_id = (i % 100).to_u32 + 1
      data = "x" * (i % 1000 + 100)

      # Create various frame types
      data_frame = H2O::DataFrame.new(stream_id, data.to_slice, 0_u8)
      headers_frame = H2O::HeadersFrame.new(stream_id, Bytes.new(100), 0_u8)
      window_frame = H2O::WindowUpdateFrame.new(stream_id, 65536_u32)

      # Simulate some processing
      data_frame.length
      headers_frame.length
      window_frame.window_size_increment
    end

    time_without_pool = Time.monotonic - start_time
    gc_without_pool = GC.stats.total_bytes - gc_start

    # Test 2: With pooling
    frame_pools = H2O::FramePoolManager.new(500)
    start_time = Time.monotonic
    gc_start = GC.stats.total_bytes

    iterations.times do |i|
      stream_id = (i % 100).to_u32 + 1
      data = "x" * (i % 1000 + 100)

      # Use pooled frames
      data_frame = frame_pools.acquire_data_frame(stream_id, data.to_slice, 0_u8)
      headers_frame = frame_pools.acquire_headers_frame(stream_id, Bytes.new(100), 0_u8)
      window_frame = frame_pools.window_update_pool.acquire
      window_frame.stream_id = stream_id
      window_frame.window_size_increment = 65536_u32

      # Simulate some processing
      data_frame.length
      headers_frame.length
      window_frame.window_size_increment

      # Release back to pool
      frame_pools.release(data_frame)
      frame_pools.release(headers_frame)
      frame_pools.release(window_frame)
    end

    time_with_pool = Time.monotonic - start_time
    gc_with_pool = GC.stats.total_bytes - gc_start

    puts "Without frame pooling:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_without_pool.total_milliseconds.round(2)}ms"
    puts "  Memory allocated: #{(gc_without_pool / 1024.0 / 1024.0).round(2)}MB"
    puts "  Average time: #{(time_without_pool.total_microseconds / iterations).round(2)}μs"

    puts "\nWith frame pooling:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_with_pool.total_milliseconds.round(2)}ms"
    puts "  Memory allocated: #{(gc_with_pool / 1024.0 / 1024.0).round(2)}MB"
    puts "  Average time: #{(time_with_pool.total_microseconds / iterations).round(2)}μs"
    puts "  Pool sizes: Data=#{frame_pools.data_frame_pool.size}, Headers=#{frame_pools.headers_frame_pool.size}"

    improvement = ((time_without_pool - time_with_pool) / time_without_pool * 100).round(1)
    mem_reduction = gc_without_pool > 0 ? ((gc_without_pool - gc_with_pool).to_f / gc_without_pool * 100).round(1) : 0

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Memory reduction: #{mem_reduction}%"
  end
end
