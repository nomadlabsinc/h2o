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

    # Performance tracking
    @@allocation_count = Atomic(Int64).new(0)
    @@return_count = Atomic(Int64).new(0)

    # Enhanced buffer allocation with size optimization
    def self.get_buffer(requested_size : Int32) : Bytes
      @@allocation_count.add(1)

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
      select
      when buffer = @@header_buffers.receive?
        buffer || Bytes.new(MAX_HEADER_BUFFER_SIZE)
      else
        Bytes.new(MAX_HEADER_BUFFER_SIZE)
      end
    end

    def self.return_header_buffer(buffer : Bytes) : Nil
      return unless buffer.size == MAX_HEADER_BUFFER_SIZE
      @@return_count.add(1)

      select
      when @@header_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
    end

    def self.get_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE) : Bytes
      if size <= MAX_FRAME_BUFFER_SIZE
        select
        when buffer = @@frame_buffers.receive?
          if buffer && buffer.size >= size
            return buffer[0, size]
          else
            Bytes.new(size)
          end
        else
          Bytes.new(size)
        end
      else
        Bytes.new(size)
      end
    end

    def self.return_frame_buffer(buffer : Bytes) : Nil
      return unless buffer.size == MAX_FRAME_BUFFER_SIZE
      @@return_count.add(1)

      select
      when @@frame_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
    end

    # New optimized small buffer pool
    def self.get_small_buffer : Bytes
      select
      when buffer = @@small_buffers.receive?
        buffer || Bytes.new(SMALL_BUFFER_SIZE)
      else
        Bytes.new(SMALL_BUFFER_SIZE)
      end
    end

    def self.return_small_buffer(buffer : Bytes) : Nil
      return unless buffer.size == SMALL_BUFFER_SIZE
      @@return_count.add(1)

      select
      when @@small_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
    end

    # New optimized medium buffer pool
    def self.get_medium_buffer : Bytes
      select
      when buffer = @@medium_buffers.receive?
        buffer || Bytes.new(MEDIUM_BUFFER_SIZE)
      else
        Bytes.new(MEDIUM_BUFFER_SIZE)
      end
    end

    def self.return_medium_buffer(buffer : Bytes) : Nil
      return unless buffer.size == MEDIUM_BUFFER_SIZE
      @@return_count.add(1)

      select
      when @@medium_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
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
      pooled_buffer = try_get_pooled_frame_buffer
      if pooled_buffer
        use_existing_frame_buffer(pooled_buffer, size) { |buffer| yield buffer }
      else
        use_new_frame_buffer(size) { |buffer| yield buffer }
      end
    end

    private def self.try_get_pooled_frame_buffer : Bytes?
      select
      when pooled_buffer = @@frame_buffers.receive?
        pooled_buffer
      else
        nil
      end
    end

    private def self.use_existing_frame_buffer(pooled_buffer : Bytes, size : Int32, & : Bytes -> T) : T forall T
      begin
        yield pooled_buffer[0, size]
      ensure
        return_frame_buffer(pooled_buffer)
      end
    end

    private def self.use_new_frame_buffer(size : Int32, & : Bytes -> T) : T forall T
      buffer = Bytes.new(MAX_FRAME_BUFFER_SIZE)
      begin
        yield buffer[0, size]
      ensure
        return_frame_buffer(buffer)
      end
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

    # Performance statistics
    def self.stats : {allocations: Int64, returns: Int64, hit_rate: Float64}
      allocs = @@allocation_count.get
      returns = @@return_count.get
      hit_rate = returns > 0 ? (returns.to_f64 / allocs.to_f64) * 100.0 : 0.0

      {allocations: allocs, returns: returns, hit_rate: hit_rate}
    end

    def self.reset_stats : Nil
      @@allocation_count.set(0)
      @@return_count.set(0)
    end
  end
end
