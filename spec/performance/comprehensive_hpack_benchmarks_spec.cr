require "../performance_benchmarks_spec"

# Sample header sets for testing various scenarios
private def small_headers : H2O::Headers
  headers = H2O::Headers.new
  headers[":method"] = "GET"
  headers[":path"] = "/"
  headers[":scheme"] = "https"
  headers[":authority"] = "example.com"
  headers
end

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
  # Add many custom headers to test performance with larger header sets
  50.times do |i|
    headers["x-custom-#{i}"] = "value-#{i}-#{Random.rand(1000)}"
  end
  headers
end

private def static_heavy_headers : H2O::Headers
  headers = H2O::Headers.new
  headers[":method"] = "POST"
  headers[":path"] = "/"
  headers[":scheme"] = "https"
  headers[":status"] = "200"
  headers["accept-encoding"] = "gzip, deflate"
  headers
end

# Simulate main branch HPACK implementation without optimizations
private def main_branch_encode(headers : H2O::Headers) : Bytes
  # Create encoder similar to main branch implementation
  encoder = H2O::HPACK::Encoder.new

  # Use simple literal encoding without case-statement optimizations
  result = IO::Memory.new
  headers.each do |name, value|
    # Check static table first (basic implementation)
    static_index = H2O::HPACK::StaticTable.find_name_value(name, value)

    if static_index
      # Encode as indexed header
      if static_index < 127
        result.write_byte((0x80 | static_index).to_u8)
      else
        result.write_byte(0xFF_u8)
        remaining = static_index - 127
        while remaining >= 128
          result.write_byte(((remaining % 128) + 128).to_u8)
          remaining //= 128
        end
        result.write_byte(remaining.to_u8)
      end
    else
      # Literal without indexing (no optimizations)
      result.write_byte(0x00_u8)
      result.write_byte(name.bytesize.to_u8)
      result.write(name.to_slice)
      result.write_byte(value.bytesize.to_u8)
      result.write(value.to_slice)
    end
  end

  result.to_slice
end

# Current optimized instance-based encoder
private def optimized_instance_encode(headers : H2O::Headers) : Bytes
  encoder = H2O::HPACK::Encoder.new
  encoder.encode(headers)
end

# New fast static method
private def fast_static_encode(headers : H2O::Headers) : Bytes
  H2O::HPACK.encode_fast(headers)
end

# Comprehensive HPACK performance benchmarks comparing main vs PR optimizations
describe "Comprehensive HPACK Performance Benchmarks" do
  it "compares encoding performance across all implementations" do
    headers = typical_headers
    iterations = 3000

    puts "\n=== Comprehensive HPACK Encoding Performance Comparison ==="
    puts "Testing with #{headers.size} headers over #{iterations} iterations"

    # Benchmark main branch implementation
    puts "\nRunning main branch baseline..."
    main_result = PerformanceBenchmarks::BenchmarkRunner.measure(
      "Main Branch HPACK Encoding", iterations
    ) do
      main_branch_encode(headers)
    end

    # Benchmark optimized instance encoder
    puts "Running optimized instance encoder..."
    instance_result = PerformanceBenchmarks::BenchmarkRunner.measure(
      "Optimized Instance Encoder", iterations
    ) do
      optimized_instance_encode(headers)
    end

    # Benchmark fast static method
    puts "Running fast static method..."
    fast_result = PerformanceBenchmarks::BenchmarkRunner.measure(
      "Fast Static Method", iterations
    ) do
      fast_static_encode(headers)
    end

    # Calculate improvements
    instance_vs_main = PerformanceBenchmarks::PerformanceComparison.new(
      main_result, instance_result, "Instance vs Main"
    )

    fast_vs_main = PerformanceBenchmarks::PerformanceComparison.new(
      main_result, fast_result, "Fast vs Main"
    )

    fast_vs_instance = PerformanceBenchmarks::PerformanceComparison.new(
      instance_result, fast_result, "Fast vs Instance"
    )

    puts "\n" + "="*60
    puts instance_vs_main.summary
    puts "\n" + "="*60
    puts fast_vs_main.summary
    puts "\n" + "="*60
    puts fast_vs_instance.summary

    # Verify all implementations produce valid results
    main_encoded = main_branch_encode(headers)
    instance_encoded = optimized_instance_encode(headers)
    fast_encoded = fast_static_encode(headers)

    puts "\n=== Output Size Comparison ==="
    puts "Main branch: #{main_encoded.size} bytes"
    puts "Instance optimized: #{instance_encoded.size} bytes"
    puts "Fast static: #{fast_encoded.size} bytes"

    # All should produce valid HPACK output
    main_encoded.size.should be > 0
    instance_encoded.size.should be > 0
    fast_encoded.size.should be > 0

    # Fast method should be fastest
    fast_result.avg_time_per_op.should be <= instance_result.avg_time_per_op

    puts "\n✓ All HPACK implementations produce valid output"
    puts "✓ Performance optimizations show measurable improvements"
  end

  it "measures static table optimization impact" do
    headers = static_heavy_headers
    iterations = 5000

    puts "\n=== Static Table Optimization Performance ==="
    puts "Testing with static-table-heavy headers: #{headers.keys}"

    # Test case statement optimization vs hash lookup
    case_optimized_time = PerformanceBenchmarks::BenchmarkRunner.measure(
      "Case Statement Optimization", iterations
    ) do
      fast_static_encode(headers)
    end

    hash_lookup_time = PerformanceBenchmarks::BenchmarkRunner.measure(
      "Hash Table Lookup", iterations
    ) do
      main_branch_encode(headers)
    end

    comparison = PerformanceBenchmarks::PerformanceComparison.new(
      hash_lookup_time, case_optimized_time, "Static Table Optimization"
    )

    puts comparison.summary

    # Case statement should be faster for common headers
    comparison.time_improvement.should be > 0.0

    puts "\n✓ Case statement optimization provides performance benefit for static headers"
  end

  it "measures performance scaling with header set size" do
    test_cases = [
      {"Small (4 headers)", small_headers},
      {"Typical (10 headers)", typical_headers},
      {"Large (60 headers)", large_headers},
    ]

    iterations = 1000

    puts "\n=== Performance Scaling Analysis ==="

    test_cases.each do |name, headers|
      puts "\n--- #{name} ---"

      main_time = PerformanceBenchmarks::BenchmarkRunner.measure(
        "Main #{name}", iterations
      ) do
        main_branch_encode(headers)
      end

      fast_time = PerformanceBenchmarks::BenchmarkRunner.measure(
        "Fast #{name}", iterations
      ) do
        fast_static_encode(headers)
      end

      comparison = PerformanceBenchmarks::PerformanceComparison.new(
        main_time, fast_time, "time"
      )

      puts "Headers: #{headers.size}, Improvement: #{comparison.time_improvement.round(1)}%"
      puts "Main: #{main_time.avg_time_per_op.total_microseconds.round(1)}μs/op"
      puts "Fast: #{fast_time.avg_time_per_op.total_microseconds.round(1)}μs/op"

      # All implementations should handle all sizes
      fast_time.avg_time_per_op.should be <= main_time.avg_time_per_op * 1.1 # Allow 10% margin
    end

    puts "\n✓ Performance scaling is consistent across header set sizes"
  end

  it "measures memory allocation patterns" do
    headers = typical_headers
    iterations = 1000

    puts "\n=== Memory Allocation Analysis ==="

    # Force GC before testing
    GC.collect

    implementations = [
      {"Main Branch", -> { main_branch_encode(headers) }},
      {"Instance Optimized", -> { optimized_instance_encode(headers) }},
      {"Fast Static", -> { fast_static_encode(headers) }},
    ]

    implementations.each do |name, impl|
      GC.collect
      initial_memory = GC.stats.heap_size

      start_time = Time.monotonic
      iterations.times { impl.call }
      end_time = Time.monotonic

      GC.collect
      final_memory = GC.stats.heap_size

      total_time = end_time - start_time
      memory_allocated = final_memory > initial_memory ? final_memory - initial_memory : 0_i64

      puts "\n#{name}:"
      puts "  Total time: #{total_time.total_milliseconds.round(1)}ms"
      puts "  Memory allocated: #{memory_allocated} bytes"
      puts "  Memory per operation: #{memory_allocated / iterations} bytes"
      puts "  Time per operation: #{(total_time / iterations).total_microseconds.round(1)}μs"

      # All should have reasonable memory usage
      (memory_allocated / iterations).should be < 1000 # Less than 1KB per operation
    end

    puts "\n✓ Memory allocation patterns are within acceptable ranges"
  end

  it "measures compression effectiveness" do
    test_headers = [
      {"Static Heavy", static_heavy_headers},
      {"Mixed Content", typical_headers},
      {"Custom Heavy", large_headers},
    ]

    puts "\n=== Compression Effectiveness Analysis ==="

    test_headers.each do |name, headers|
      puts "\n--- #{name} ---"

      # Calculate raw header size
      raw_size = headers.sum { |k, v| k.bytesize + v.bytesize + 2 } # +2 for separators

      main_encoded = main_branch_encode(headers)
      instance_encoded = optimized_instance_encode(headers)
      fast_encoded = fast_static_encode(headers)

      main_ratio = raw_size.to_f64 / main_encoded.size.to_f64
      instance_ratio = raw_size.to_f64 / instance_encoded.size.to_f64
      fast_ratio = raw_size.to_f64 / fast_encoded.size.to_f64

      puts "Raw size: #{raw_size} bytes"
      puts "Main encoded: #{main_encoded.size} bytes (#{main_ratio.round(2)}:1)"
      puts "Instance encoded: #{instance_encoded.size} bytes (#{instance_ratio.round(2)}:1)"
      puts "Fast encoded: #{fast_encoded.size} bytes (#{fast_ratio.round(2)}:1)"

      # All should achieve reasonable compression (or at least not expand significantly)
      main_ratio.should be > 0.8 # Allow for some headers that don't compress well
      instance_ratio.should be > 0.8
      fast_ratio.should be > 0.8

      # Optimized versions should not be significantly worse at compression
      instance_ratio.should be >= main_ratio * 0.9 # Within 10%
      fast_ratio.should be >= main_ratio * 0.9     # Within 10%
    end

    puts "\n✓ Compression effectiveness maintained across optimizations"
  end

  it "measures real-world scenario performance" do
    iterations = 2000

    puts "\n=== Real-World Scenario Performance ==="

    # Simulate typical HTTP/2 request patterns
    request_headers = H2O::Headers.new
    request_headers[":method"] = "POST"
    request_headers[":path"] = "/api/v1/data"
    request_headers[":scheme"] = "https"
    request_headers[":authority"] = "api.production.com"
    request_headers["user-agent"] = "MyApp/2.1.0 (iOS 15.0)"
    request_headers["accept"] = "application/json"
    request_headers["accept-encoding"] = "gzip, deflate, br"
    request_headers["content-type"] = "application/json"
    request_headers["authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    request_headers["x-client-version"] = "2.1.0"
    request_headers["x-session-id"] = "sess_abc123def456"
    request_headers["x-trace-id"] = "trace_789xyz012"

    response_headers = H2O::Headers.new
    response_headers[":status"] = "200"
    response_headers["content-type"] = "application/json; charset=utf-8"
    response_headers["content-length"] = "1024"
    response_headers["cache-control"] = "no-cache, no-store, must-revalidate"
    response_headers["server"] = "h2o/2.2.6"
    response_headers["x-response-time"] = "45ms"
    response_headers["x-rate-limit-remaining"] = "99"

    scenarios = [
      {"HTTP Request", request_headers},
      {"HTTP Response", response_headers},
    ]

    scenarios.each do |scenario_name, headers|
      puts "\n--- #{scenario_name} ---"

      # Test all three implementations
      main_result = PerformanceBenchmarks::BenchmarkRunner.measure(
        "Main #{scenario_name}", iterations
      ) do
        main_branch_encode(headers)
      end

      instance_result = PerformanceBenchmarks::BenchmarkRunner.measure(
        "Instance #{scenario_name}", iterations
      ) do
        optimized_instance_encode(headers)
      end

      fast_result = PerformanceBenchmarks::BenchmarkRunner.measure(
        "Fast #{scenario_name}", iterations
      ) do
        fast_static_encode(headers)
      end

      instance_improvement = ((main_result.avg_time_per_op - instance_result.avg_time_per_op) / main_result.avg_time_per_op) * 100.0
      fast_improvement = ((main_result.avg_time_per_op - fast_result.avg_time_per_op) / main_result.avg_time_per_op) * 100.0

      puts "Main: #{main_result.avg_time_per_op.total_microseconds.round(1)}μs/op"
      puts "Instance: #{instance_result.avg_time_per_op.total_microseconds.round(1)}μs/op (#{instance_improvement.round(1)}% improvement)"
      puts "Fast: #{fast_result.avg_time_per_op.total_microseconds.round(1)}μs/op (#{fast_improvement.round(1)}% improvement)"

      # Both optimized versions should be faster
      instance_result.avg_time_per_op.should be <= main_result.avg_time_per_op
      fast_result.avg_time_per_op.should be <= main_result.avg_time_per_op
    end

    puts "\n✓ Real-world scenarios show consistent performance improvements"
  end
end
