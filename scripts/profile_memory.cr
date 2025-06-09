#!/usr/bin/env crystal

# Memory profiling script for H2O client
# Tracks allocations and memory usage patterns

require "../src/h2o"
require "log"

Log.setup(:warn)

class MemoryProfiler
  record AllocationSnapshot,
    label : String,
    heap_size : Int64,
    total_bytes : Int64,
    time : Time::Span

  @snapshots : Array(AllocationSnapshot)
  @start_time : Time::Monotonic
  @initial_heap : Int64
  @initial_bytes : Int64

  def initialize
    @snapshots = [] of AllocationSnapshot
    @start_time = Time.monotonic
    @initial_heap = GC.stats.heap_size
    @initial_bytes = GC.stats.total_bytes

    snapshot("Initial state")
  end

  def snapshot(label : String)
    GC.collect
    @snapshots << AllocationSnapshot.new(
      label: label,
      heap_size: GC.stats.heap_size,
      total_bytes: GC.stats.total_bytes,
      time: Time.monotonic - @start_time
    )
  end

  def report
    puts "\n=== Memory Profile Report ==="
    puts "Duration: #{(Time.monotonic - @start_time).total_seconds.round(2)}s"
    puts "\nSnapshots:"

    @snapshots.each_with_index do |snap, i|
      heap_delta = snap.heap_size - @initial_heap
      bytes_delta = snap.total_bytes - @initial_bytes

      puts "\n[#{i}] #{snap.label} (#{snap.time.total_milliseconds.round(0)}ms)"
      puts "  Heap: #{(snap.heap_size / 1024.0 / 1024.0).round(2)}MB (#{heap_delta > 0 ? "+" : ""}#{(heap_delta / 1024.0 / 1024.0).round(2)}MB)"
      puts "  Total allocated: #{(snap.total_bytes / 1024.0 / 1024.0).round(2)}MB (#{bytes_delta > 0 ? "+" : ""}#{(bytes_delta / 1024.0 / 1024.0).round(2)}MB)"

      if i > 0
        prev = @snapshots[i - 1]
        heap_growth = snap.heap_size - prev.heap_size
        bytes_growth = snap.total_bytes - prev.total_bytes
        time_delta = snap.time - prev.time

        puts "  Since last: +#{(bytes_growth / 1024.0).round(2)}KB in #{time_delta.total_milliseconds.round(0)}ms"
        puts "  Rate: #{(bytes_growth / time_delta.total_seconds / 1024.0 / 1024.0).round(2)}MB/s"
      end
    end

    # Overall statistics
    final_snap = @snapshots.last
    total_allocated = final_snap.total_bytes - @initial_bytes
    avg_rate = total_allocated / final_snap.time.total_seconds

    puts "\n=== Overall Statistics ==="
    puts "Total memory allocated: #{(total_allocated / 1024.0 / 1024.0).round(2)}MB"
    puts "Average allocation rate: #{(avg_rate / 1024.0 / 1024.0).round(2)}MB/s"
    puts "Heap growth: #{((final_snap.heap_size - @initial_heap) / 1024.0 / 1024.0).round(2)}MB"
  end
end

def profile_basic_operations
  puts "=== Profiling Basic Operations ==="
  profiler = MemoryProfiler.new
  client = H2O::Client.new

  profiler.snapshot("Client created")

  # Single request
  response = client.get("https://www.google.com/")
  profiler.snapshot("First request completed")

  # Multiple requests
  10.times do |i|
    response = client.get("https://www.google.com/search?q=test#{i}")
  end
  profiler.snapshot("10 requests completed")

  # Requests with headers
  headers = H2O::Headers{
    "user-agent"    => "H2O Profiler",
    "accept"        => "text/html",
    "cache-control" => "no-cache",
  }

  10.times do |i|
    response = client.get("https://www.google.com/search?q=headers#{i}", headers)
  end
  profiler.snapshot("10 requests with headers")

  # Large response
  begin
    response = client.get("https://httpbin.org/bytes/1048576") # 1MB
    profiler.snapshot("Large response received")
  rescue
    profiler.snapshot("Large response failed")
  end

  client.close
  profiler.snapshot("Client closed")

  profiler.report
end

def profile_object_pooling
  puts "\n=== Profiling Object Pooling ==="
  profiler = MemoryProfiler.new

  # Simulate heavy frame allocation/deallocation
  1000.times do |i|
    frame = H2O::DataFrame.new(1_u32, "test data #{i}".to_slice, 0x1_u8)
    # In real implementation, this would be returned to pool
    if i % 100 == 99
      profiler.snapshot("#{i + 1} frames created")
    end
  end

  profiler.report
end

def profile_string_interning
  puts "\n=== Profiling String Interning ==="
  profiler = MemoryProfiler.new

  pool = H2O.string_pool
  pool.clear
  profiler.snapshot("String pool cleared")

  # Common headers that should be interned
  common_headers = [
    "content-type", "content-length", "user-agent",
    "accept", "accept-encoding", "cache-control",
  ]

  # Simulate many requests with same headers
  1000.times do |i|
    headers = H2O::Headers.new
    common_headers.each do |name|
      headers[pool.intern(name)] = pool.intern("value-#{name}")
    end

    if i % 200 == 199
      profiler.snapshot("#{i + 1} header sets created")
    end
  end

  stats = pool.statistics
  puts "\nString Pool Statistics:"
  puts "  Pool size: #{pool.size} strings"
  puts "  Hit rate: #{(stats.hit_rate * 100).round(1)}%"
  puts "  Memory saved: #{(stats.bytes_saved / 1024.0).round(2)}KB"

  profiler.report
end

def main
  puts "H2O Memory Profiler"
  puts "=================="

  profile_basic_operations
  profile_object_pooling
  profile_string_interning

  puts "\n=== Profiling Complete ==="
end

main
