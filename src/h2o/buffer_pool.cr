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

    # Enhanced pools with multiple size categories
    @@header_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)
    @@frame_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)
    @@small_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)
    @@medium_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)

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
      # Disabled pooling to avoid memory issues
      Bytes.new(MAX_HEADER_BUFFER_SIZE)
    end

    def self.return_header_buffer(buffer : Bytes) : Nil
      # Pooling is disabled - just track stats if enabled
      stats = H2O.buffer_pool_stats?
      stats.track_return if stats

      # Let buffer be garbage collected
    end

    def self.get_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE) : Bytes
      # Disabled pooling to avoid memory issues
      Bytes.new(size)
    end

    def self.return_frame_buffer(buffer : Bytes) : Nil
      # Pooling is disabled - just track stats if enabled
      stats = H2O.buffer_pool_stats?
      stats.track_return if stats

      # Let buffer be garbage collected
    end

    # New optimized small buffer pool
    def self.get_small_buffer : Bytes
      # Disabled pooling to avoid memory issues
      Bytes.new(SMALL_BUFFER_SIZE)
    end

    def self.return_small_buffer(buffer : Bytes) : Nil
      # Pooling is disabled - just track stats if enabled
      stats = H2O.buffer_pool_stats?
      stats.track_return if stats

      # Let buffer be garbage collected
    end

    # New optimized medium buffer pool
    def self.get_medium_buffer : Bytes
      # Disabled pooling to avoid memory issues
      Bytes.new(MEDIUM_BUFFER_SIZE)
    end

    def self.return_medium_buffer(buffer : Bytes) : Nil
      # Pooling is disabled - just track stats if enabled
      stats = H2O.buffer_pool_stats?
      stats.track_return if stats

      # Let buffer be garbage collected
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
      if size <= MAX_FRAME_BUFFER_SIZE
        use_pooled_frame_buffer(size) { |buffer| yield buffer }
      else
        use_large_frame_buffer(size) { |buffer| yield buffer }
      end
    end

    private def self.use_pooled_frame_buffer(size : Int32, & : Bytes -> T) : T forall T
      # Pooling is disabled - always create new buffer
      use_new_frame_buffer(size) { |buffer| yield buffer }
    end

    # These methods are no longer used since pooling is disabled
    # Kept for potential future re-enablement

    private def self.use_new_frame_buffer(size : Int32, & : Bytes -> T) : T forall T
      buffer = Bytes.new(MAX_FRAME_BUFFER_SIZE)
      yield buffer[0, size]
      # No need to return buffer since pooling is disabled
    end

    private def self.use_large_frame_buffer(size : Int32, & : Bytes -> T) : T forall T
      buffer = Bytes.new(size)
      yield buffer
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
    def self.stats : {allocations: Int64, returns: Int64, hit_rate: Float64}
      if stats = H2O.buffer_pool_stats?
        stats.stats
      else
        {allocations: 0_i64, returns: 0_i64, hit_rate: 0.0}
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
