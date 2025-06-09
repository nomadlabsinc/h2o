require "../performance_benchmarks_spec"

# Mock stream for baseline comparison (without optimizations)
private class MockStreamBaseline
  property id : UInt32
  property state : String
  property created_at : Time
  property closed_at : Time?

  def initialize(@id : UInt32)
    @state = "idle"
    @created_at = Time.utc
    @closed_at = nil
  end

  def transition_to(new_state : String) : Nil
    # Simple state change without validation
    @state = new_state
    @closed_at = Time.utc if new_state == "closed"
  end

  def closed? : Bool
    @state == "closed"
  end

  def age : Time::Span
    end_time = @closed_at || Time.utc
    end_time - @created_at
  end
end

# Simple stream pool for baseline
private class SimpleStreamPool
  @streams = Hash(UInt32, MockStreamBaseline).new
  @next_id : UInt32 = 1_u32

  def create_stream : MockStreamBaseline
    stream = MockStreamBaseline.new(@next_id)
    @streams[@next_id] = stream
    @next_id += 2
    stream
  end

  def remove_stream(id : UInt32) : Nil
    @streams.delete(id)
  end

  def active_streams : Array(MockStreamBaseline)
    @streams.values.reject(&.closed?)
  end

  def stream_count : Int32
    active_streams.size
  end

  def cleanup_closed_streams : Nil
    @streams.reject! { |_, stream| stream.closed? }
  end
end

describe "Stream Management Performance Benchmarks" do
  it "measures stream object pooling performance" do
    iterations = 5000
    predicted_improvement = 22.0 # 20-25% predicted

    puts "\n=== Stream Object Pooling Performance Test ==="

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Direct Stream Allocation",
      "Pooled Stream Allocation",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Simulate direct allocation without pooling
        pool = SimpleStreamPool.new
        stream = pool.create_stream
        stream.transition_to("open")
        stream.transition_to("closed")
        pool.remove_stream(stream.id)
      },
      -> {
        # Use optimized stream pool with object pooling
        pool = H2O::StreamPool.new
        stream = pool.create_stream
        stream.state = H2O::StreamState::Open
        stream.state = H2O::StreamState::Closed
        pool.remove_stream(stream.id)
      }
    )

    puts comparison.summary

    # Stream pooling should reduce allocation overhead
    comparison.time_improvement.should be > 10.0

    puts "\n✓ Stream object pooling shows measurable performance improvement"
    puts "  Time improvement: #{comparison.time_improvement.round(1)}% (target: 20-25%)"
  end

  it "measures stream state transition performance" do
    iterations = 10000
    predicted_improvement = 15.0

    puts "\n=== Stream State Transition Performance Test ==="

    # Test state transitions
    stream = H2O::Stream.new(1_u32)

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Simple State Change",
      "Validated State Transition",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Direct state assignment (unsafe)
        mock_stream = MockStreamBaseline.new(1_u32)
        mock_stream.transition_to("open")
        mock_stream.transition_to("half_closed_local")
        mock_stream.transition_to("closed")
      },
      -> {
        # Optimized state transitions with validation
        test_stream = H2O::Stream.new(1_u32)
        headers = H2O::Headers.new
        headers[":method"] = "GET"
        encoded_headers = H2O::HPACK.encode_fast(headers)
        headers_frame = H2O::HeadersFrame.new(1_u32, encoded_headers, H2O::HeadersFrame::FLAG_END_HEADERS)
        test_stream.send_headers(headers_frame)
        # Reset for next iteration
        test_stream.state = H2O::StreamState::Idle
      }
    )

    puts comparison.summary

    # Optimized transitions should be efficient despite validation
    comparison.time_improvement.should be > 0.0 # At least no degradation

    puts "\n✓ Optimized state transitions maintain performance"
  end

  it "measures stream priority queue performance" do
    stream_count = 1000
    iterations = 100

    puts "\n=== Stream Priority Queue Performance Test ==="

    pool = H2O::StreamPool.new

    # Create streams with different priorities
    streams = Array(H2O::Stream).new
    stream_count.times do |i|
      stream = pool.create_stream
      priority = (i % 32).to_u8 # Distribute across priority range
      stream.set_priority(priority)
      streams << stream
    end

    start_time = Time.monotonic

    iterations.times do
      # Get prioritized streams (this involves sorting)
      prioritized = pool.prioritized_streams
      prioritized.size # Force evaluation
    end

    end_time = Time.monotonic
    total_time = end_time - start_time

    avg_time = total_time / iterations
    puts "Stream count: #{stream_count}"
    puts "Iterations: #{iterations}"
    puts "Average prioritization time: #{avg_time.total_milliseconds.round(3)}ms"
    puts "Streams per second: #{(stream_count.to_f64 / avg_time.total_seconds).round(0)}"

    # Should handle prioritization efficiently
    avg_time.should be < 10.milliseconds

    # Cleanup
    streams.each { |stream| pool.remove_stream(stream.id) }

    puts "\n✓ Stream priority queue performs efficiently"
  end

  it "measures flow control optimization performance" do
    stream_count = 500
    iterations = 200

    puts "\n=== Flow Control Optimization Performance Test ==="

    pool = H2O::StreamPool.new

    # Create streams and set various window sizes
    streams = Array(H2O::Stream).new
    stream_count.times do |_|
      stream = pool.create_stream
      # Vary window sizes to create different flow control states
      stream.local_window_size = Random.rand(0..65535)
      stream.remote_window_size = Random.rand(0..65535)
      streams << stream
    end

    start_time = Time.monotonic

    iterations.times do
      # Check streams needing window updates
      needing_updates = pool.streams_needing_window_update

      # Check streams ready for data
      ready_for_data = pool.streams_ready_for_data

      # Force evaluation
      needing_updates.size + ready_for_data.size
    end

    end_time = Time.monotonic
    total_time = end_time - start_time

    avg_time = total_time / iterations
    puts "Stream count: #{stream_count}"
    puts "Flow control checks: #{iterations}"
    puts "Average check time: #{avg_time.total_milliseconds.round(3)}ms"

    # Should efficiently filter streams by flow control state
    avg_time.should be < 5.milliseconds

    # Cleanup
    streams.each { |stream| pool.remove_stream(stream.id) }

    puts "\n✓ Flow control optimization performs efficiently"
  end

  it "measures stream lifecycle tracking performance" do
    iterations = 2000
    predicted_improvement = 18.0

    puts "\n=== Stream Lifecycle Tracking Performance Test ==="

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Basic Stream Management",
      "Enhanced Lifecycle Tracking",
      "time",
      iterations,
      predicted_improvement,
      -> {
        # Simple stream management
        pool = SimpleStreamPool.new
        stream = pool.create_stream
        stream.transition_to("open")
        stream.transition_to("closed")
        pool.remove_stream(stream.id)
        pool.cleanup_closed_streams
      },
      -> {
        # Enhanced stream management with lifecycle tracking
        pool = H2O::StreamPool.new
        stream = pool.create_stream

        # Simulate frame operations that trigger lifecycle events
        headers = H2O::Headers.new
        headers[":method"] = "GET"
        encoded_headers = H2O::HPACK.encode_fast(headers)
        headers_frame = H2O::HeadersFrame.new(stream.id, encoded_headers)
        stream.receive_headers(headers_frame, headers)

        data_frame = H2O::DataFrame.new(stream.id, Bytes.new(100), H2O::DataFrame::FLAG_END_STREAM)
        stream.receive_data(data_frame)

        pool.remove_stream(stream.id)
        pool.cleanup_closed_streams
      }
    )

    puts comparison.summary

    # Enhanced tracking should not significantly impact performance
    comparison.time_improvement.should be > -10.0 # Allow small degradation for extra features

    puts "\n✓ Enhanced lifecycle tracking maintains good performance"
  end

  it "measures concurrent stream operations performance" do
    fiber_count = 10
    operations_per_fiber = 100

    puts "\n=== Concurrent Stream Operations Test ==="

    pool = H2O::StreamPool.new

    start_time = Time.monotonic

    # Use channel for fiber synchronization
    completion_channel = Channel(Nil).new(fiber_count)

    fiber_count.times do |_|
      spawn do
        operations_per_fiber.times do |_|
          stream = pool.create_stream

          # Simulate stream operations
          headers = H2O::Headers.new
          headers[":method"] = "GET"
          headers[":path"] = "/test"

          encoded_headers = H2O::HPACK.encode_fast(headers)
          headers_frame = H2O::HeadersFrame.new(stream.id, encoded_headers)
          stream.receive_headers(headers_frame, headers)

          data_frame = H2O::DataFrame.new(stream.id, Bytes.new(50), H2O::DataFrame::FLAG_END_STREAM)
          stream.receive_data(data_frame)

          pool.remove_stream(stream.id)
        end
        completion_channel.send(nil)
      end
    end

    # Wait for all fibers to complete
    fiber_count.times { completion_channel.receive }

    end_time = Time.monotonic
    total_time = end_time - start_time

    total_operations = fiber_count * operations_per_fiber
    avg_time = total_time / total_operations

    puts "Concurrent fibers: #{fiber_count}"
    puts "Operations per fiber: #{operations_per_fiber}"
    puts "Total operations: #{total_operations}"
    puts "Total time: #{total_time.total_milliseconds.round(1)}ms"
    puts "Average time per operation: #{avg_time.total_milliseconds.round(3)}ms"
    puts "Operations per second: #{(total_operations.to_f64 / total_time.total_seconds).round(0)}"

    # Should handle concurrent operations efficiently
    avg_time.should be < 1.milliseconds
    total_time.should be < 10.seconds

    puts "\n✓ Concurrent stream operations perform efficiently"
  end

  it "measures stream cache effectiveness" do
    operations = 2000

    puts "\n=== Stream Cache Effectiveness Test ==="

    pool = H2O::StreamPool.new

    # Perform operations that should benefit from caching
    start_time = Time.monotonic

    streams = Array(H2O::Stream).new
    operations.times do |i|
      stream = pool.create_stream
      streams << stream

      if i % 100 == 0
        # Periodically access active streams (should use cache)
        active = pool.active_streams
        closed = pool.closed_streams
        active.size + closed.size # Force evaluation
      end
    end

    # Close half the streams
    streams[0, streams.size // 2].each do |stream|
      stream.state = H2O::StreamState::Closed
    end

    # Access cached results multiple times
    10.times do
      active = pool.active_streams
      closed = pool.closed_streams
      active.size + closed.size
    end

    end_time = Time.monotonic
    total_time = end_time - start_time

    puts "Total operations: #{operations}"
    puts "Total time: #{total_time.total_milliseconds.round(1)}ms"
    puts "Average time per operation: #{(total_time.total_milliseconds / operations).round(3)}ms"

    final_stats = pool.state_metrics
    puts "Final stream state distribution: #{final_stats}"

    # Should complete efficiently with caching
    (total_time.total_milliseconds / operations).should be < 0.1

    # Cleanup
    streams.each { |stream| pool.remove_stream(stream.id) }

    puts "\n✓ Stream caching provides effective performance benefit"
  end

  it "measures memory efficiency in stream operations" do
    iterations = 1000

    puts "\n=== Stream Memory Efficiency Test ==="

    GC.collect
    initial_memory = GC.stats.heap_size

    pool = H2O::StreamPool.new

    iterations.times do |i|
      stream = pool.create_stream

      # Simulate typical stream lifecycle
      headers = H2O::Headers.new
      headers[":method"] = "GET"
      headers[":path"] = "/api/data"

      encoded_headers = H2O::HPACK.encode_fast(headers)
      headers_frame = H2O::HeadersFrame.new(stream.id, encoded_headers)
      stream.receive_headers(headers_frame, headers)

      # Send some data
      data_frame = H2O::DataFrame.new(stream.id, Bytes.new(1024), H2O::DataFrame::FLAG_END_STREAM)
      stream.receive_data(data_frame)

      pool.remove_stream(stream.id)

      # Periodic cleanup
      if i % 100 == 0
        pool.cleanup_closed_streams
        GC.collect if i % 500 == 0
      end
    end

    pool.cleanup_closed_streams
    GC.collect
    final_memory = GC.stats.heap_size

    memory_growth = final_memory - initial_memory
    memory_per_stream = memory_growth / iterations

    puts "Initial memory: #{initial_memory} bytes"
    puts "Final memory: #{final_memory} bytes"
    puts "Memory growth: #{memory_growth} bytes"
    puts "Memory per stream operation: #{memory_per_stream} bytes"

    # Check object pool statistics
    pool_stats = H2O::StreamObjectPool.pool_stats
    puts "Stream object pool statistics: #{pool_stats}"

    # Memory growth should be reasonable
    memory_per_stream.should be < 5000 # Less than 5KB per stream

    puts "\n✓ Stream memory usage is well controlled"
  end
end
