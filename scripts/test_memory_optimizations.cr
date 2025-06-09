#!/usr/bin/env crystal

# Manual test script for memory management optimizations
# Tests real HTTP/2 servers and monitors memory usage

require "../src/h2o"
require "log"

Log.setup(:info)

def print_memory_stats(label : String)
  puts "\n#{label}:"
  puts "  Heap size: #{(GC.stats.heap_size / 1024.0 / 1024.0).round(2)}MB"
  puts "  Total bytes: #{(GC.stats.total_bytes / 1024.0 / 1024.0).round(2)}MB"
  GC.collect
end

def test_google_com
  puts "\n=== Testing against google.com ==="
  client = H2O::Client.new

  print_memory_stats("Before requests")

  # Make multiple requests
  10.times do |i|
    response = client.get("https://www.google.com/search?q=test#{i}")
    if response
      puts "Request #{i + 1}: #{response.status} - #{response.body.size} bytes"
    else
      puts "Request #{i + 1}: Failed"
    end
  end

  print_memory_stats("After 10 requests")

  # Make more requests to test memory growth
  90.times do |i|
    response = client.get("https://www.google.com/search?q=test#{i + 10}")
  end

  print_memory_stats("After 100 requests")

  client.close
rescue ex
  puts "Error testing google.com: #{ex.message}"
end

def test_cloudflare
  puts "\n=== Testing against cloudflare.com ==="
  client = H2O::Client.new

  print_memory_stats("Before requests")

  # Test with common headers that should be interned
  headers = H2O::Headers{
    "user-agent"      => "H2O Test Client",
    "accept"          => "text/html,application/xhtml+xml",
    "accept-encoding" => "gzip, deflate, br",
    "cache-control"   => "no-cache",
  }

  50.times do |i|
    response = client.get("https://www.cloudflare.com/", headers)
    if response && i % 10 == 0
      puts "Request #{i + 1}: #{response.status}"
    end
  end

  print_memory_stats("After 50 requests with headers")

  # Check string pool statistics
  pool_stats = H2O.string_pool.statistics
  puts "\nString Pool Stats:"
  puts "  Pool size: #{H2O.string_pool.size} strings"
  puts "  Cache hits: #{pool_stats.hits}"
  puts "  Hit rate: #{(pool_stats.hit_rate * 100).round(1)}%"
  puts "  Bytes saved: #{(pool_stats.bytes_saved / 1024.0).round(2)}KB"

  client.close
rescue ex
  puts "Error testing cloudflare.com: #{ex.message}"
end

def test_httpbin
  puts "\n=== Testing against httpbin.org ==="
  client = H2O::Client.new

  print_memory_stats("Before requests")

  # Test various response sizes
  sizes = [1024, 10240, 102400]

  sizes.each do |size|
    5.times do |i|
      response = client.get("https://httpbin.org/bytes/#{size}")
      if response && i == 0
        puts "Size #{size}: #{response.status} - #{response.body.size} bytes"
      end
    end
  end

  print_memory_stats("After variable size responses")

  client.close
rescue ex
  puts "Error testing httpbin.org: #{ex.message}"
end

def main
  puts "HTTP/2 Memory Optimization Manual Test"
  puts "======================================"

  initial_memory = GC.stats.heap_size

  # Clear string pool to start fresh
  H2O.string_pool.clear

  # Run tests
  test_google_com
  test_cloudflare
  test_httpbin

  # Final memory report
  final_memory = GC.stats.heap_size
  memory_growth = final_memory - initial_memory

  puts "\n=== Final Memory Report ==="
  puts "Initial heap: #{(initial_memory / 1024.0 / 1024.0).round(2)}MB"
  puts "Final heap: #{(final_memory / 1024.0 / 1024.0).round(2)}MB"
  puts "Growth: #{(memory_growth / 1024.0 / 1024.0).round(2)}MB"

  # Final string pool stats
  pool_stats = H2O.string_pool.statistics
  puts "\nFinal String Pool Statistics:"
  puts "  Total strings interned: #{H2O.string_pool.size}"
  puts "  Total lookups: #{pool_stats.hits + pool_stats.misses}"
  puts "  Cache hit rate: #{(pool_stats.hit_rate * 100).round(1)}%"
  puts "  Total memory saved: #{(pool_stats.bytes_saved / 1024.0).round(2)}KB"
end

main
