require "../spec_helper"
require "../../src/h2o"

describe "Memory Management Baseline Performance" do
  it "measures baseline object allocation performance" do
    puts "\n=== BASELINE Object Allocation Performance ==="

    # Test different object types that are frequently created
    iterations = 100_000

    # Test 1: Stream object creation
    start_time = Time.monotonic
    streams = Array(H2O::Stream).new

    iterations.times do |i|
      stream = H2O::Stream.new((i % 1000).to_u32 + 1)
      streams << stream if i < 100 # Keep only first 100 to avoid OOM
    end

    stream_creation_time = Time.monotonic - start_time

    # Test 2: Frame object creation
    start_time = Time.monotonic
    frames = Array(H2O::Frame).new

    iterations.times do |i|
      frame = H2O::DataFrame.new((i % 1000).to_u32 + 1, "test data".to_slice, 0_u8)
      frames << frame if i < 100
    end

    frame_creation_time = Time.monotonic - start_time

    # Test 3: String allocation for headers
    start_time = Time.monotonic
    header_names = ["accept", "accept-encoding", "accept-language", "cache-control",
                    "content-type", "cookie", "host", "user-agent"]
    header_strings = Array(String).new

    iterations.times do |i|
      name = header_names[i % header_names.size]
      # Simulate string duplication that happens in header processing
      dup_name = name.dup
      header_strings << dup_name if i < 100
    end

    string_alloc_time = Time.monotonic - start_time

    puts "Stream object creation:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{stream_creation_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(stream_creation_time.total_microseconds / iterations).round(2)}μs"
    puts "  Objects per second: #{(iterations / stream_creation_time.total_seconds).round(0)}"

    puts "\nFrame object creation:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{frame_creation_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(frame_creation_time.total_microseconds / iterations).round(2)}μs"
    puts "  Objects per second: #{(iterations / frame_creation_time.total_seconds).round(0)}"

    puts "\nString allocation (headers):"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{string_alloc_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(string_alloc_time.total_microseconds / iterations).round(2)}μs"
    puts "  Allocations per second: #{(iterations / string_alloc_time.total_seconds).round(0)}"
  end

  it "measures baseline memory pressure and GC impact" do
    puts "\n=== Memory Pressure and GC Impact ==="

    # Force GC before test
    GC.collect

    initial_memory = GC.stats.heap_size

    # Create many objects to trigger GC
    iterations = 50_000
    start_time = Time.monotonic
    gc_bytes_start = GC.stats.total_bytes

    iterations.times do |i|
      # Create various objects that would typically be created in HTTP/2 processing
      stream = H2O::Stream.new((i % 1000).to_u32 + 1)
      frame = H2O::DataFrame.new(stream.id, ("x" * 100).to_slice, 0_u8)
      headers = H2O::Headers{"content-type" => "text/plain", "content-length" => "100"}

      # Simulate some processing
      stream.id.to_s
      frame.length.to_s
      headers.size.to_s
    end

    elapsed_time = Time.monotonic - start_time
    gc_bytes_end = GC.stats.total_bytes
    final_memory = GC.stats.heap_size

    gc_allocated = gc_bytes_end - gc_bytes_start
    memory_growth = final_memory - initial_memory

    puts "Test duration: #{elapsed_time.total_milliseconds.round(2)}ms"
    puts "Objects created: #{iterations * 3}"
    puts "Total bytes allocated: #{(gc_allocated / 1024.0 / 1024.0).round(2)}MB"
    puts "Memory growth: #{(memory_growth / 1024.0 / 1024.0).round(2)}MB"
    puts "Average time per iteration: #{(elapsed_time.total_microseconds / iterations).round(2)}μs"

    # Force final GC and measure cleanup
    GC.collect
    cleaned_memory = GC.stats.heap_size
    memory_cleaned = final_memory - cleaned_memory

    puts "Memory after GC: #{(cleaned_memory / 1024.0 / 1024.0).round(2)}MB"
    puts "Memory cleaned: #{(memory_cleaned / 1024.0 / 1024.0).round(2)}MB"
  end

  it "measures string interning potential for common headers" do
    puts "\n=== String Interning Potential ==="

    common_headers = [
      ":method", ":path", ":scheme", ":authority", ":status",
      "accept", "accept-encoding", "accept-language", "cache-control",
      "content-type", "content-length", "cookie", "date", "etag",
      "host", "if-modified-since", "if-none-match", "last-modified",
      "location", "referer", "server", "set-cookie", "user-agent",
      "vary", "via", "x-forwarded-for", "x-requested-with",
    ]

    iterations = 100_000

    # Test 1: Without interning (current approach)
    start_time = Time.monotonic
    header_instances = Array(String).new

    iterations.times do |i|
      header = common_headers[i % common_headers.size]
      # Simulate creating new string instance each time
      new_header = header.dup
      header_instances << new_header if i < 1000
    end

    time_without_interning = Time.monotonic - start_time

    # Calculate memory usage
    total_bytes = 0
    header_instances.each { |header| total_bytes += header.bytesize }

    puts "Without interning:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{time_without_interning.total_milliseconds.round(2)}ms"
    puts "  Sample memory usage (first 1000): #{total_bytes} bytes"
    puts "  Unique strings: #{common_headers.size}"
    puts "  String instances created: #{iterations}"
    puts "  Memory waste factor: #{(iterations.to_f / common_headers.size).round(1)}x"
  end
end
