# Separate statistics tracking that can be instance-based for testing
module H2O
  # Statistics tracker for buffer pool - can be instance-based for testing
  class BufferPoolStats
    @allocation_count = Atomic(Int64).new(0)
    @return_count = Atomic(Int64).new(0)

    def track_allocation : Nil
      @allocation_count.add(1)
    end

    def track_return : Nil
      @return_count.add(1)
    end

    def stats : {allocations: Int64, returns: Int64, hit_rate: Float64}
      allocs = @allocation_count.get
      returns = @return_count.get
      hit_rate = returns > 0 ? (returns.to_f64 / allocs.to_f64) * 100.0 : 0.0

      {allocations: allocs, returns: returns, hit_rate: hit_rate}
    end

    def reset : Nil
      @allocation_count.set(0)
      @return_count.set(0)
    end
  end

  # Global stats instance (optional)
  @@buffer_pool_stats : BufferPoolStats? = nil

  def self.buffer_pool_stats : BufferPoolStats
    @@buffer_pool_stats ||= BufferPoolStats.new
  end

  def self.buffer_pool_stats? : BufferPoolStats?
    @@buffer_pool_stats
  end

  def self.enable_buffer_pool_stats : BufferPoolStats
    @@buffer_pool_stats = BufferPoolStats.new
  end

  def self.disable_buffer_pool_stats : Nil
    @@buffer_pool_stats = nil
  end
end
