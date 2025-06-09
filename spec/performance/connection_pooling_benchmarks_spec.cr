require "../performance_benchmarks_spec"

# Mock connection class for testing
private class MockConnection
  property closed : Bool = false
  property created_at : Time
  property request_count : Int32 = 0
  property error_count : Int32 = 0
  property response_times : Array(Time::Span) = [] of Time::Span

  def initialize
    @created_at = Time.utc
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  def make_request(simulate_error : Bool = false) : String
    start_time = Time.monotonic

    # Simulate some work
    sleep(Random.rand(0.001..0.005).seconds)

    end_time = Time.monotonic
    response_time = end_time - start_time

    @request_count += 1
    @response_times << response_time

    if simulate_error
      @error_count += 1
      raise "Simulated error"
    end

    "response"
  end

  def avg_response_time : Time::Span
    return Time::Span.zero if @response_times.empty?
    total = @response_times.sum
    total / @response_times.size
  end

  def error_rate : Float64
    return 0.0 if @request_count == 0
    @error_count.to_f64 / @request_count.to_f64
  end
end

# Simple connection pool for baseline comparison
private class SimpleConnectionPool
  @connections = Hash(String, MockConnection).new
  @max_size : Int32

  def initialize(@max_size : Int32 = 10)
  end

  def get_connection(host : String) : MockConnection
    key = host
    existing = @connections[key]?

    if existing && !existing.closed?
      return existing
    end

    # Create new connection
    connection = MockConnection.new

    # Enforce size limit by removing oldest
    if @connections.size >= @max_size
      oldest_key = @connections.keys.first?
      if oldest_key
        @connections[oldest_key]?.try(&.close)
        @connections.delete(oldest_key)
      end
    end

    @connections[key] = connection
    connection
  end

  def close_all
    @connections.each_value(&.close)
    @connections.clear
  end

  def size
    @connections.size
  end

  def connection_stats
    active = @connections.values.count { |connection| !connection.closed? }
    total_requests = @connections.values.sum(&.request_count)
    total_errors = @connections.values.sum(&.error_count)

    {
      active_connections: active,
      total_connections:  @connections.size,
      total_requests:     total_requests,
      total_errors:       total_errors,
    }
  end
end

# Enhanced connection pool with scoring (simulating our optimized version)
private class EnhancedConnectionPool
  @connections = Hash(String, MockConnection).new
  @connection_scores = Hash(String, Float64).new
  @max_size : Int32

  def initialize(@max_size : Int32 = 10)
  end

  def get_connection(host : String) : MockConnection
    key = host
    existing = @connections[key]?

    if existing && !existing.closed? && connection_healthy?(existing)
      # Update score based on usage
      update_connection_score(key, existing)
      return existing
    end

    # Create new connection
    connection = MockConnection.new

    # Enforce size limit using scoring
    if @connections.size >= @max_size
      evict_worst_connection
    end

    @connections[key] = connection
    @connection_scores[key] = 100.0
    connection
  end

  def close_all
    @connections.each_value(&.close)
    @connections.clear
    @connection_scores.clear
  end

  def size
    @connections.size
  end

  def connection_stats
    active = @connections.values.count { |connection| !connection.closed? }
    total_requests = @connections.values.sum(&.request_count)
    total_errors = @connections.values.sum(&.error_count)
    avg_score = @connection_scores.values.sum / @connection_scores.size.to_f64

    {
      active_connections: active,
      total_connections:  @connections.size,
      total_requests:     total_requests,
      total_errors:       total_errors,
      average_score:      avg_score,
    }
  end

  private def connection_healthy?(connection : MockConnection) : Bool
    # Check age (don't use connections older than 1 hour in simulation)
    age = Time.utc - connection.created_at
    return false if age > 1.hour

    # Check error rate
    return false if connection.error_rate > 0.5

    true
  end

  private def update_connection_score(key : String, connection : MockConnection) : Nil
    base_score = 100.0

    # Penalty for errors
    error_penalty = connection.error_rate * 50.0

    # Penalty for slow responses
    avg_time = connection.avg_response_time.total_milliseconds
    speed_penalty = [avg_time / 10.0, 30.0].min

    # Bonus for recency
    age_minutes = (Time.utc - connection.created_at).total_minutes
    age_bonus = [20.0 - age_minutes, 0.0].max

    score = base_score - error_penalty - speed_penalty + age_bonus
    @connection_scores[key] = score
  end

  private def evict_worst_connection : Nil
    worst_key = nil
    worst_score = Float64::MAX

    @connection_scores.each do |key, score|
      if score < worst_score
        worst_score = score
        worst_key = key
      end
    end

    if worst_key
      @connections[worst_key]?.try(&.close)
      @connections.delete(worst_key)
      @connection_scores.delete(worst_key)
    end
  end
end

describe "Connection Pooling Performance Benchmarks" do
  it "measures connection reuse performance improvement" do
    iterations = 1000
    predicted_improvement = 45.0 # 40-50% predicted

    puts "\n=== Connection Reuse Performance Test ==="

    hosts = ["api1.example.com", "api2.example.com", "api3.example.com"]

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Simple Connection Pool",
      "Enhanced Connection Pool",
      "time",
      iterations,
      predicted_improvement,
      -> {
        pool = SimpleConnectionPool.new(5)
        iterations.times do |i|
          host = hosts[i % hosts.size]
          connection = pool.get_connection(host)
          begin
            connection.make_request
          rescue
            # Handle errors
          end
        end
        pool.close_all
      },
      -> {
        pool = EnhancedConnectionPool.new(5)
        iterations.times do |i|
          host = hosts[i % hosts.size]
          connection = pool.get_connection(host)
          begin
            connection.make_request
          rescue
            # Handle errors
          end
        end
        pool.close_all
      }
    )

    puts comparison.summary

    # Enhanced pool should show improvement due to better connection selection
    comparison.time_improvement.should be > 10.0

    puts "\n✓ Connection reuse shows measurable performance improvement"
  end

  it "measures connection scoring effectiveness" do
    iterations = 500

    puts "\n=== Connection Scoring Effectiveness Test ==="

    pool = EnhancedConnectionPool.new(3)
    hosts = ["good-host.com", "slow-host.com", "error-host.com"]

    # Make requests with different patterns
    iterations.times do |i|
      host_index = i % hosts.size
      host = hosts[host_index]

      connection = pool.get_connection(host)

      begin
        case host_index
        when 0 # Good host
          connection.make_request(false)
        when 1 # Slow host - simulate with extra sleep
          sleep(0.002.seconds)
          connection.make_request(false)
        when 2 # Error host
          connection.make_request(true) if Random.rand < 0.3
        end
      rescue
        # Handle errors
      end
    end

    stats = pool.connection_stats
    puts "Final connection statistics:"
    puts "  Active connections: #{stats[:active_connections]}"
    puts "  Total requests: #{stats[:total_requests]}"
    puts "  Total errors: #{stats[:total_errors]}"
    puts "  Average score: #{stats[:average_score].round(1)}"

    # Should maintain reasonable connection health
    stats[:active_connections].should be > 0
    stats[:average_score].should be > 60.0 # Reasonable average score

    pool.close_all

    puts "\n✓ Connection scoring effectively manages connection quality"
  end

  it "measures connection warm-up performance" do
    hosts = ["api1.example.com", "api2.example.com", "api3.example.com"]
    requests_per_host = 100

    puts "\n=== Connection Warm-up Performance Test ==="

    # Test without warm-up (cold start)
    cold_start_time = Time.monotonic
    hosts.each do |host|
      pool = SimpleConnectionPool.new(1)
      requests_per_host.times do
        connection = pool.get_connection(host)
        connection.make_request
      end
      pool.close_all
    end
    cold_time = Time.monotonic - cold_start_time

    # Test with warm-up (simulated)
    warm_start_time = Time.monotonic
    pool = EnhancedConnectionPool.new(hosts.size)

    # Pre-warm connections
    hosts.each do |host|
      pool.get_connection(host)
    end

    # Now make requests
    hosts.each do |host|
      requests_per_host.times do
        connection = pool.get_connection(host)
        connection.make_request
      end
    end
    pool.close_all
    warm_time = Time.monotonic - warm_start_time

    improvement = ((cold_time - warm_time) / cold_time) * 100.0

    puts "Cold start time: #{cold_time.total_milliseconds.round(1)}ms"
    puts "Warm start time: #{warm_time.total_milliseconds.round(1)}ms"
    puts "Improvement: #{improvement.round(1)}%"

    # Warm-up should provide some benefit
    improvement.should be > 5.0

    puts "\n✓ Connection warm-up provides measurable benefit"
  end

  it "measures concurrent connection access performance" do
    fiber_count = 20
    requests_per_fiber = 50
    hosts = ["api1.example.com", "api2.example.com", "api3.example.com"]

    puts "\n=== Concurrent Connection Access Test ==="

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Simple Pool Concurrent",
      "Enhanced Pool Concurrent",
      "time",
      1, # Single test
      30.0,
      -> {
        pool = SimpleConnectionPool.new(10)
        completion_channel = Channel(Nil).new(fiber_count)

        fiber_count.times do |i|
          spawn do
            requests_per_fiber.times do |j|
              host = hosts[(i + j) % hosts.size]
              connection = pool.get_connection(host)
              connection.make_request
            end
            completion_channel.send(nil)
          end
        end

        fiber_count.times { completion_channel.receive }
        pool.close_all
      },
      -> {
        pool = EnhancedConnectionPool.new(10)
        completion_channel = Channel(Nil).new(fiber_count)

        fiber_count.times do |i|
          spawn do
            requests_per_fiber.times do |j|
              host = hosts[(i + j) % hosts.size]
              connection = pool.get_connection(host)
              connection.make_request
            end
            completion_channel.send(nil)
          end
        end

        fiber_count.times { completion_channel.receive }
        pool.close_all
      }
    )

    puts comparison.summary

    total_requests = fiber_count * requests_per_fiber
    puts "Total concurrent requests: #{total_requests}"

    # Should handle concurrent access efficiently
    comparison.time_improvement.should be > 0.0 # At least no degradation

    puts "\n✓ Enhanced connection pool handles concurrency efficiently"
  end

  it "measures connection lifecycle management overhead" do
    iterations = 200
    max_connections = 5

    puts "\n=== Connection Lifecycle Management Test ==="

    # Test rapid connection creation/destruction
    start_time = Time.monotonic

    pool = EnhancedConnectionPool.new(max_connections)

    iterations.times do |i|
      # Create connections for different hosts
      host = "host-#{i}.example.com"
      connection = pool.get_connection(host)
      connection.make_request

      # This will trigger eviction when pool is full
    end

    end_time = Time.monotonic
    total_time = end_time - start_time

    stats = pool.connection_stats

    puts "Total operations: #{iterations}"
    puts "Total time: #{total_time.total_milliseconds.round(1)}ms"
    puts "Time per operation: #{(total_time.total_milliseconds / iterations).round(3)}ms"
    puts "Final pool size: #{pool.size}"
    puts "Active connections: #{stats[:active_connections]}"

    # Should complete efficiently
    (total_time.total_milliseconds / iterations).should be < 1.0 # Less than 1ms per operation

    pool.close_all

    puts "\n✓ Connection lifecycle management is efficient"
  end

  it "measures protocol caching simulation" do
    hosts = ["h2-server.com", "h1-server.com", "mixed-server.com"]
    iterations = 300

    puts "\n=== Protocol Caching Performance Test ==="

    # Simulate protocol detection overhead
    protocol_cache = Hash(String, String).new

    # Test without caching
    no_cache_time = Time.monotonic
    iterations.times do |i|
      host = hosts[i % hosts.size]
      # Simulate protocol detection (expensive operation)
      sleep(0.001.seconds) # 1ms detection time
      protocol = ["http/1.1", "http/2"].sample
    end
    no_cache_duration = Time.monotonic - no_cache_time

    # Test with caching
    cache_time = Time.monotonic
    iterations.times do |i|
      host = hosts[i % hosts.size]

      if cached_protocol = protocol_cache[host]?
        # Use cached protocol (fast)
        protocol = cached_protocol
      else
        # Detect protocol (expensive)
        sleep(0.001.seconds)
        protocol = ["http/1.1", "http/2"].sample
        protocol_cache[host] = protocol
      end
    end
    cache_duration = Time.monotonic - cache_time

    improvement = ((no_cache_duration - cache_duration) / no_cache_duration) * 100.0

    puts "Without caching: #{no_cache_duration.total_milliseconds.round(1)}ms"
    puts "With caching: #{cache_duration.total_milliseconds.round(1)}ms"
    puts "Improvement: #{improvement.round(1)}%"
    puts "Cache entries: #{protocol_cache.size}"

    # Protocol caching should provide significant benefit
    improvement.should be > 60.0 # Major improvement expected

    puts "\n✓ Protocol caching provides significant performance benefit"
  end
end
