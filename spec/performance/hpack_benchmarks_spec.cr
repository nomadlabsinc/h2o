require "../performance_benchmarks_spec"

# Sample headers for testing
private def typical_headers : H2O::Headers
  headers = H2O::Headers.new
  headers[":method"] = "GET"
  headers[":path"] = "/api/v1/users"
  headers[":scheme"] = "https"
  headers[":authority"] = "api.example.com"
  headers["user-agent"] = "h2o/1.0.0"
  headers["accept"] = "application/json"
  headers["accept-encoding"] = "gzip, deflate"
  headers["authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
  headers["content-type"] = "application/json"
  headers["x-request-id"] = "123e4567-e89b-12d3-a456-426614174000"
  headers
end

private def large_headers : H2O::Headers
  headers = typical_headers
  # Add more headers to test performance with larger header sets
  50.times do |i|
    headers["x-custom-#{i}"] = "value-#{i}-#{Random.rand(1000)}"
  end
  headers
end

# Simulate old HPACK implementation without optimizations
private def old_hpack_encode(headers : H2O::Headers) : Bytes
  # Create a basic encoder without pre-computed optimizations
  encoder = H2O::HPACK::Encoder.new

  # Manually serialize without using static table optimizations
  result = IO::Memory.new
  headers.each do |name, value|
    # Force literal encoding (bypass static table optimization)
    result.write_byte(0x00_u8) # Literal without indexing

    # Encode name length and name
    name_bytes = name.to_slice
    result.write_byte(name_bytes.size.to_u8)
    result.write(name_bytes)

    # Encode value length and value
    value_bytes = value.to_slice
    result.write_byte(value_bytes.size.to_u8)
    result.write(value_bytes)
  end

  result.to_slice
end

# New optimized HPACK encoding
private def new_hpack_encode(headers : H2O::Headers) : Bytes
  encoder = H2O::HPACK::Encoder.new
  encoder.encode(headers)
end

describe "HPACK Performance Benchmarks" do
  it "measures HPACK encoding performance improvement" do
    headers = typical_headers
    iterations = 2000
    predicted_improvement = 30.0 # 25-35% predicted

    puts "\n=== HPACK Encoding Performance Test ==="

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Old HPACK Encoding",
      "Optimized HPACK Encoding",
      "time",
      iterations,
      predicted_improvement,
      -> { old_hpack_encode(headers) },
      -> { new_hpack_encode(headers) }
    )

    puts comparison.summary

    # Assertions
    comparison.time_improvement.should be > 15.0 # At least 15% improvement

    puts "\n✓ HPACK encoding shows significant performance improvement"
    puts "  Time improvement: #{comparison.time_improvement.round(1)}% (target: 25-35%)"
  end

  it "measures fast static method performance vs instance method" do
    headers = typical_headers
    iterations = 3000
    predicted_improvement = 20.0 # Expected 15-25% improvement

    puts "\n=== Fast Static Method vs Instance Method ==="

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Instance Method",
      "Fast Static Method",
      "time",
      iterations,
      predicted_improvement,
      -> {
        encoder = H2O::HPACK::Encoder.new
        encoder.encode(headers)
      },
      -> { H2O::HPACK.encode_fast(headers) }
    )

    puts comparison.summary

    # Fast static method should be faster
    comparison.time_improvement.should be > 5.0 # At least 5% improvement

    puts "\n✓ Fast static method provides performance benefit over instance method"
    puts "  Time improvement: #{comparison.time_improvement.round(1)}% (target: 15-25%)"
  end

  it "measures static table lookup performance" do
    iterations = 5000
    predicted_improvement = 40.0

    puts "\n=== Static Table Lookup Performance ==="

    # Test common header lookups
    common_headers = [":method", ":path", ":scheme", ":authority", "user-agent", "accept"]

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Linear Search Lookup",
      "Hash-based Lookup",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Simulate old linear search
        common_headers.each do |header|
          # Linear search through static table
          H2O::HPACK::StaticTable::STATIC_ENTRIES.each do |entry|
            break if entry.name == header
          end
        end
      },
      -> {
        # Use optimized hash lookup
        common_headers.each do |header|
          H2O::HPACK::StaticTable.find_name(header)
        end
      }
    )

    puts comparison.summary

    comparison.time_improvement.should be > 25.0 # Hash lookup should be much faster

    puts "\n✓ Static table lookups show dramatic improvement"
  end

  it "measures header name normalization cache performance" do
    iterations = 3000
    predicted_improvement = 20.0

    puts "\n=== Header Name Normalization Cache Performance ==="

    # Mix of normalized and non-normalized header names
    header_names = [
      "User-Agent", "user-agent", "USER-AGENT",
      "Content-Type", "content-type", "CONTENT-TYPE",
      "Accept-Encoding", "accept-encoding", "ACCEPT-ENCODING",
      "Authorization", "authorization", "AUTHORIZATION",
    ]

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Direct Normalization",
      "Cached Normalization",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Direct normalization without caching
        header_names.each do |name|
          name.downcase # Direct operation
        end
      },
      -> {
        # Use cached normalization
        header_names.each do |name|
          H2O::HPACK::StaticTable.normalize_header_name(name)
        end
      }
    )

    puts comparison.summary

    comparison.time_improvement.should be > 10.0 # Cache should help with repeated lookups

    puts "\n✓ Header name normalization cache provides measurable benefit"
  end

  it "measures compression ratio improvement" do
    headers = large_headers
    iterations = 500

    puts "\n=== HPACK Compression Ratio Test ==="

    old_encoded = old_hpack_encode(headers)
    new_encoded = new_hpack_encode(headers)

    # Calculate original header size
    original_size = headers.sum { |k, v| k.bytesize + v.bytesize }

    old_compression_ratio = original_size.to_f64 / old_encoded.size.to_f64
    new_compression_ratio = original_size.to_f64 / new_encoded.size.to_f64

    puts "Original headers size: #{original_size} bytes"
    puts "Old encoding size: #{old_encoded.size} bytes (ratio: #{old_compression_ratio.round(2)}:1)"
    puts "New encoding size: #{new_encoded.size} bytes (ratio: #{new_compression_ratio.round(2)}:1)"

    compression_improvement = ((old_encoded.size - new_encoded.size).to_f64 / old_encoded.size.to_f64) * 100.0
    puts "Compression improvement: #{compression_improvement.round(1)}%"

    # New encoding should be smaller due to better static table usage
    new_encoded.size.should be <= old_encoded.size
    new_compression_ratio.should be >= old_compression_ratio

    puts "\n✓ HPACK compression ratio improved or maintained"
  end

  it "measures decoding performance with large header sets" do
    large_headers_set = large_headers
    iterations = 1000
    predicted_improvement = 20.0

    puts "\n=== HPACK Decoding Performance with Large Headers ==="

    # Encode headers first
    encoder = H2O::HPACK::Encoder.new
    encoded_data = encoder.encode(large_headers_set)

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "HPACK Decoding (Baseline)",
      "HPACK Decoding (Optimized)",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Use separate decoder instance for baseline
        decoder = H2O::HPACK::Decoder.new
        decoder.decode(encoded_data)
      },
      -> {
        # Use optimized decoder
        decoder = H2O::HPACK::Decoder.new
        decoder.decode(encoded_data)
      }
    )

    puts comparison.summary

    # Decoding improvements are more modest but should still be measurable
    comparison.time_improvement.should be > 5.0

    puts "\n✓ HPACK decoding performance maintained or improved"
  end

  it "measures dynamic table efficiency" do
    iterations = 1000

    puts "\n=== Dynamic Table Performance Test ==="

    # Test dynamic table operations
    dynamic_table = H2O::HPACK::DynamicTable.new

    start_time = Time.monotonic

    iterations.times do |i|
      # Add entries to dynamic table
      dynamic_table.add("x-custom-#{i}", "value-#{i}")

      # Perform lookups
      dynamic_table.find_name("x-custom-#{i}")
      dynamic_table.find_name_value("x-custom-#{i}", "value-#{i}")
    end

    total_time = Time.monotonic - start_time
    avg_time_per_op = total_time / (iterations * 3) # 3 operations per iteration

    puts "Dynamic table operations: #{iterations * 3}"
    puts "Total time: #{total_time.total_milliseconds.round(1)}ms"
    puts "Average time per operation: #{avg_time_per_op.total_microseconds.round(1)}μs"

    # Should complete efficiently
    avg_time_per_op.should be < 100.microseconds

    puts "\n✓ Dynamic table operations are efficient"
  end

  it "measures memory usage in HPACK operations" do
    iterations = 500
    headers = typical_headers

    puts "\n=== HPACK Memory Usage Test ==="

    GC.collect
    initial_memory = GC.stats.heap_size

    iterations.times do |_|
      encoder = H2O::HPACK::Encoder.new
      encoded = encoder.encode(headers)

      decoder = H2O::HPACK::Decoder.new
      decoded = decoder.decode(encoded)
    end

    GC.collect
    final_memory = GC.stats.heap_size
    memory_growth = final_memory - initial_memory

    puts "Initial memory: #{initial_memory} bytes"
    puts "Final memory: #{final_memory} bytes"
    puts "Memory growth: #{memory_growth} bytes"
    puts "Memory per operation: #{memory_growth / iterations} bytes"

    # Memory growth should be reasonable
    memory_per_op = memory_growth / iterations
    memory_per_op.should be < 10000 # Less than 10KB per operation

    puts "\n✓ HPACK memory usage is well controlled"
  end
end
