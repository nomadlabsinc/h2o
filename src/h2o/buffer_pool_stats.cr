# Separate statistics tracking that can be instance-based for testing
module H2O
  # Statistics tracker for buffer pool - can be instance-based for testing
  class BufferPoolStats
    @allocation_count = Atomic(Int64).new(0)
    @hit_count = Atomic(Int64).new(0)
    @return_count = Atomic(Int64).new(0)
    @mutex = Mutex.new

    def track_allocation : Nil
      @allocation_count.add(1)
    end

    def track_hit : Nil
      @hit_count.add(1)
    end

    def track_return : Nil
      @return_count.add(1)
    end

    def stats : {allocations: Int64, hits: Int64, returns: Int64, hit_rate: Float64}
      allocs = @allocation_count.get
      hits = @hit_count.get
      returns = @return_count.get
      total_requests = allocs + hits
      hit_rate = total_requests > 0 ? (hits.to_f64 / total_requests.to_f64) * 100.0 : 0.0

      {allocations: allocs, hits: hits, returns: returns, hit_rate: hit_rate}
    end

    def reset : Nil
      @mutex.synchronize do
        @allocation_count.set(0)
        @hit_count.set(0)
        @return_count.set(0)
      end
    end
  end

  # DISABLED: Global stats to prevent malloc corruption
  # Each client should have its own stats instance if needed
  # @@buffer_pool_stats : BufferPoolStats? = nil

  # Dummy stats class that does nothing to avoid any concurrency issues
  class DummyBufferPoolStats < BufferPoolStats
    def track_allocation : Nil
      # No-op
    end

    def track_hit : Nil
      # No-op
    end

    def track_return : Nil
      # No-op
    end

    def stats : {allocations: Int64, hits: Int64, returns: Int64, hit_rate: Float64}
      {allocations: 0_i64, hits: 0_i64, returns: 0_i64, hit_rate: 0.0}
    end

    def reset : Nil
      # No-op - nothing to reset
    end
  end

  # Create a single dummy instance to avoid allocation issues
  DUMMY_STATS = DummyBufferPoolStats.new

  def self.buffer_pool_stats : BufferPoolStats
    # Return the same dummy instance to avoid repeated allocations
    DUMMY_STATS
  end

  def self.buffer_pool_stats? : BufferPoolStats?
    # Always return nil to disable stats tracking
    nil
  end

  def self.enable_buffer_pool_stats : BufferPoolStats
    # No-op - stats are disabled, return dummy instance
    DUMMY_STATS
  end

  def self.disable_buffer_pool_stats : Nil
    # No-op - stats are disabled
  end
end
