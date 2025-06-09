#!/usr/bin/env crystal

# Load test for memory optimizations under high concurrency
# Tests object pooling and string interning under load

require "../src/h2o"
require "log"

Log.setup(:warn) # Reduce log noise during load test

class LoadTester
  @client : H2O::Client
  @url : String
  @requests_per_fiber : Int32
  @fiber_count : Int32
  @results : Channel(NamedTuple(success: Bool, time: Time::Span, memory: Int64))

  def initialize(@url : String, @fiber_count : Int32, @requests_per_fiber : Int32)
    @client = H2O::Client.new
    @results = Channel(NamedTuple(success: Bool, time: Time::Span, memory: Int64)).new(@fiber_count * @requests_per_fiber)
  end

  def run
    puts "\n=== Load Test: #{@url} ==="
    puts "Fibers: #{@fiber_count}, Requests per fiber: #{@requests_per_fiber}"
    puts "Total requests: #{@fiber_count * @requests_per_fiber}"

    # Clear pools for fresh test
    H2O.string_pool.clear
    GC.collect

    initial_memory = GC.stats.total_bytes
    start_time = Time.monotonic

    # Launch concurrent fibers
    @fiber_count.times do |fiber_id|
      spawn do
        fiber_memory_start = GC.stats.total_bytes

        @requests_per_fiber.times do |req_id|
          req_start = Time.monotonic

          # Use common headers that should benefit from interning
          headers = H2O::Headers{
            "accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "accept-encoding" => "gzip, deflate, br",
            "accept-language" => "en-US,en;q=0.9",
            "cache-control"   => "no-cache",
            "user-agent"      => "H2O/1.0 LoadTest Fiber-#{fiber_id}",
            "x-request-id"    => "fiber-#{fiber_id}-req-#{req_id}",
          }

          success = false
          begin
            response = @client.get(@url, headers)
            success = response.try(&.status) == 200
          rescue
            # Ignore errors during load test
          end

          req_time = Time.monotonic - req_start
          fiber_memory = GC.stats.total_bytes - fiber_memory_start

          @results.send({success: success, time: req_time, memory: fiber_memory})
        end
      end
    end

    # Collect results
    successful = 0
    total_time = Time::Span.zero
    max_time = Time::Span.zero
    min_time = Time::Span::MAX

    total_requests = @fiber_count * @requests_per_fiber
    total_requests.times do
      result = @results.receive
      successful += 1 if result[:success]
      total_time += result[:time]
      max_time = result[:time] if result[:time] > max_time
      min_time = result[:time] if result[:time] < min_time
    end

    elapsed = Time.monotonic - start_time
    final_memory = GC.stats.total_bytes
    memory_used = final_memory - initial_memory

    # Calculate statistics
    avg_time = total_time / total_requests
    requests_per_second = total_requests / elapsed.total_seconds

    puts "\nResults:"
    puts "  Total time: #{elapsed.total_seconds.round(2)}s"
    puts "  Successful: #{successful}/#{total_requests} (#{(successful * 100.0 / total_requests).round(1)}%)"
    puts "  Requests/sec: #{requests_per_second.round(0)}"
    puts "  Avg response time: #{avg_time.total_milliseconds.round(2)}ms"
    puts "  Min response time: #{min_time.total_milliseconds.round(2)}ms"
    puts "  Max response time: #{max_time.total_milliseconds.round(2)}ms"
    puts "  Memory used: #{(memory_used / 1024.0 / 1024.0).round(2)}MB"
    puts "  Memory per request: #{(memory_used / total_requests / 1024.0).round(2)}KB"

    # String pool statistics
    pool_stats = H2O.string_pool.statistics
    puts "\nString Pool Performance:"
    puts "  Strings interned: #{H2O.string_pool.size}"
    puts "  Total lookups: #{pool_stats.hits + pool_stats.misses}"
    puts "  Cache hit rate: #{(pool_stats.hit_rate * 100).round(1)}%"
    puts "  Memory saved: #{(pool_stats.bytes_saved / 1024.0 / 1024.0).round(2)}MB"

    @client.close
  end
end

def compare_with_baseline
  puts "\n=== Comparing With/Without Optimizations ==="

  # Note: This would require a way to disable optimizations
  # For now, we'll just show the current performance
  puts "Current implementation uses memory optimizations by default"
  puts "To compare with baseline, you would need to modify the code"
end

def main
  puts "HTTP/2 Memory Optimization Load Test"
  puts "==================================="

  # Test different load scenarios
  scenarios = [
    {url: "https://www.google.com/", fibers: 10, requests: 10},
    {url: "https://www.cloudflare.com/", fibers: 20, requests: 25},
    {url: "https://httpbin.org/status/200", fibers: 50, requests: 20},
  ]

  scenarios.each do |scenario|
    begin
      tester = LoadTester.new(scenario[:url], scenario[:fibers], scenario[:requests])
      tester.run

      # Let system settle between tests
      GC.collect
      sleep 1
    rescue ex
      puts "Error testing #{scenario[:url]}: #{ex.message}"
    end
  end

  compare_with_baseline

  puts "\n=== Load Test Complete ==="
end

main
