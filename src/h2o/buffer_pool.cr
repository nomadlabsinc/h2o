module H2O
  # Enhanced buffer pool with size categories and performance optimizations
  class BufferPool
    # Maintain backwards compatibility while adding optimizations
    MAX_HEADER_BUFFER_SIZE = 64 * 1024
    MAX_FRAME_BUFFER_SIZE  = 16 * 1024 * 1024
    DEFAULT_POOL_SIZE      = 20

    # New hierarchical categories for better memory management
    SMALL_BUFFER_SIZE  = 1024
    MEDIUM_BUFFER_SIZE = 8 * 1024
    LARGE_BUFFER_SIZE  = 64 * 1024
    FRAME_BUFFER_SIZE  = 16 * 1024 * 1024

    # Fiber-safe buffer pools using channels with protected initialization
    @@small_pool : Channel(Bytes)?
    @@medium_pool : Channel(Bytes)?
    @@header_pool : Channel(Bytes)?
    @@frame_pool : Channel(Bytes)?
    @@pool_mutex = Mutex.new
    @@initialized = Atomic(Bool).new(false)
    
    # Initialize all pools at once to avoid partial initialization issues
    private def self.ensure_pools_initialized
      return if @@initialized.get
      
      @@pool_mutex.synchronize do
        return if @@initialized.get
        
        @@small_pool = Channel(Bytes).new(DEFAULT_POOL_SIZE)
        @@medium_pool = Channel(Bytes).new(DEFAULT_POOL_SIZE)  
        @@header_pool = Channel(Bytes).new(DEFAULT_POOL_SIZE)
        @@frame_pool = Channel(Bytes).new(DEFAULT_POOL_SIZE // 2)
        
        @@initialized.set(true)
      end
    end
    
    private def self.small_pool
      ensure_pools_initialized
      @@small_pool.not_nil!
    end
    
    private def self.medium_pool
      ensure_pools_initialized
      @@medium_pool.not_nil!
    end
    
    private def self.header_pool
      ensure_pools_initialized
      @@header_pool.not_nil!
    end
    
    private def self.frame_pool
      ensure_pools_initialized
      @@frame_pool.not_nil!
    end

    # Enhanced buffer allocation with size optimization
    def self.get_buffer(requested_size : Int32) : Bytes
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.track_allocation if stats

      case requested_size
      when 0..SMALL_BUFFER_SIZE
        get_small_buffer
      when (SMALL_BUFFER_SIZE + 1)..MEDIUM_BUFFER_SIZE
        get_medium_buffer
      when (MEDIUM_BUFFER_SIZE + 1)..LARGE_BUFFER_SIZE
        get_header_buffer
      else
        get_frame_buffer(requested_size)
      end
    end

    def self.get_header_buffer : Bytes
      # Try to get from pool first, otherwise allocate new
      select
      when buffer = header_pool.receive
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_hit)
        buffer
      else
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_allocation)
        Bytes.new(MAX_HEADER_BUFFER_SIZE)
      end
    end

    def self.return_header_buffer(buffer : Bytes) : Nil
      # Only return buffers of correct size to pool
      if buffer.size == MAX_HEADER_BUFFER_SIZE
        # Try to return to pool, drop if full
        select
        when header_pool.send(buffer)
          # Successfully returned to pool
        else
          # Pool is full, buffer will be garbage collected
        end
      end
      
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.try(&.track_return)
    end

    def self.get_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE) : Bytes
      # For standard size, try pool first
      if size == MAX_FRAME_BUFFER_SIZE
        select
        when buffer = frame_pool.receive
          # Optional statistics tracking
          stats = H2O.buffer_pool_stats?
          stats.try(&.track_hit)
          return buffer
        else
          # Pool is empty, fall through to allocation
        end
      end
      
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.try(&.track_allocation)
      Bytes.new(size)
    end

    def self.return_frame_buffer(buffer : Bytes) : Nil
      # Only return standard size buffers to pool
      if buffer.size == MAX_FRAME_BUFFER_SIZE
        # Try to return to pool, drop if full
        select
        when frame_pool.send(buffer)
          # Successfully returned to pool
        else
          # Pool is full, buffer will be garbage collected
        end
      end
      
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.try(&.track_return)
    end

    # New optimized small buffer pool
    def self.get_small_buffer : Bytes
      # Try to get from pool first, otherwise allocate new
      select
      when buffer = small_pool.receive
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_hit)
        buffer
      else
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_allocation)
        Bytes.new(SMALL_BUFFER_SIZE)
      end
    end

    def self.return_small_buffer(buffer : Bytes) : Nil
      # Only return buffers of correct size to pool
      if buffer.size == SMALL_BUFFER_SIZE
        # Try to return to pool, drop if full
        select
        when small_pool.send(buffer)
          # Successfully returned to pool
        else
          # Pool is full, buffer will be garbage collected
        end
      end
      
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.try(&.track_return)
    end

    # New optimized medium buffer pool
    def self.get_medium_buffer : Bytes
      # Try to get from pool first, otherwise allocate new
      select
      when buffer = medium_pool.receive
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_hit)
        buffer
      else
        # Optional statistics tracking
        stats = H2O.buffer_pool_stats?
        stats.try(&.track_allocation)
        Bytes.new(MEDIUM_BUFFER_SIZE)
      end
    end

    def self.return_medium_buffer(buffer : Bytes) : Nil
      # Only return buffers of correct size to pool
      if buffer.size == MEDIUM_BUFFER_SIZE
        # Try to return to pool, drop if full
        select
        when medium_pool.send(buffer)
          # Successfully returned to pool
        else
          # Pool is full, buffer will be garbage collected
        end
      end
      
      # Optional statistics tracking
      stats = H2O.buffer_pool_stats?
      stats.try(&.track_return)
    end

    # Generic return method for enhanced API
    def self.return_buffer(buffer : Bytes) : Nil
      case buffer.size
      when SMALL_BUFFER_SIZE
        return_small_buffer(buffer)
      when MEDIUM_BUFFER_SIZE
        return_medium_buffer(buffer)
      when MAX_HEADER_BUFFER_SIZE
        return_header_buffer(buffer)
      when MAX_FRAME_BUFFER_SIZE
        return_frame_buffer(buffer)
      end
    end

    def self.with_header_buffer(& : Bytes -> T) : T forall T
      buffer = get_header_buffer
      begin
        yield buffer
      ensure
        return_header_buffer(buffer)
      end
    end

    def self.with_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE, & : Bytes -> T) : T forall T
      buffer = get_frame_buffer(size)
      begin
        yield buffer
      ensure
        return_frame_buffer(buffer)
      end
    end


    # Enhanced with_buffer for optimized sizes
    def self.with_buffer(size : Int32, & : Bytes -> T) : T forall T
      buffer = get_buffer(size)
      begin
        yield buffer
      ensure
        return_buffer(buffer)
      end
    end

    # Performance statistics (only available when stats tracking is enabled)
    def self.stats : {allocations: Int64, hits: Int64, returns: Int64, hit_rate: Float64}
      if stats = H2O.buffer_pool_stats?
        stats.stats
      else
        {allocations: 0_i64, hits: 0_i64, returns: 0_i64, hit_rate: 0.0}
      end
    end

    def self.reset_stats : Nil
      if stats = H2O.buffer_pool_stats?
        stats.reset
      end
    end

    # Enable statistics tracking (mainly for testing/benchmarking)
    def self.enable_stats : Nil
      H2O.enable_buffer_pool_stats
    end

    # Disable statistics tracking
    def self.disable_stats : Nil
      H2O.disable_buffer_pool_stats
    end
  end
end
