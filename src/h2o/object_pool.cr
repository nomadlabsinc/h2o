module H2O
  # Generic object pool for reducing allocations using fiber-safe channels
  class ObjectPool(T)
    property pool : Channel(T)
    property capacity : Int32
    property factory : Proc(T)
    property reset : Proc(T, Nil)?

    def initialize(@capacity : Int32, @factory : Proc(T), @reset : Proc(T, Nil)? = nil)
      @pool = Channel(T).new(@capacity)
    end

    def acquire : T
      # Try to get from pool first, otherwise create new
      select
      when item = @pool.receive
        item
      else
        @factory.call
      end
    end

    def release(item : T) : Nil
      # Reset the object if reset proc provided
      @reset.try(&.call(item))
      
      # Try to return to pool, drop if full
      select
      when @pool.send(item)
        # Successfully returned to pool
      else
        # Pool is full, item will be garbage collected
      end
    end

    def size : Int32
      # Not available with channel-based implementation
      # This would require additional synchronization
      0
    end

    def clear : Nil
      # Drain the channel non-blocking
      loop do
        select
        when @pool.receive
          # Item consumed, continue loop
        else
          # Channel is empty, exit loop
          break
        end
      end
    end
  end

  # Stream object pool for performance optimization
  class StreamObjectPool
    property pool : ObjectPool(Stream)

    def initialize(capacity : Int32 = 1000)
      factory = -> { Stream.new(0_u32) }
      reset = ->(stream : Stream) do
        # Reset stream to initial state
        stream.reset_for_reuse(0_u32)
        nil
      end

      @pool = ObjectPool(Stream).new(capacity, factory, reset)
    end

    def acquire(stream_id : StreamId) : Stream
      stream = @pool.acquire
      stream.id = stream_id
      stream
    end

    def release(stream : Stream) : Nil
      @pool.release(stream)
    end

    # Static pool instance
    @@instance : StreamObjectPool? = nil

    def self.instance : StreamObjectPool
      @@instance ||= StreamObjectPool.new
    end

    def self.get_stream(stream_id : StreamId) : Stream
      instance.acquire(stream_id)
    end

    def self.release_stream(stream : Stream) : Nil
      instance.release(stream)
    end
  end

  # Simplified frame pool manager without reset methods for stability
  # Since reset_for_reuse methods are disabled, we use a simpler approach
  class FramePoolManager
    def initialize(capacity : Int32 = 500)
      # For now, disable pooling until reset methods are stable
    end

    def acquire_data_frame(stream_id : StreamId, data : Bytes, flags : UInt8) : DataFrame
      # Create new frame without pooling for now
      DataFrame.new(stream_id, data, flags)
    end

    def acquire_headers_frame(stream_id : StreamId, header_block : Bytes, flags : UInt8) : HeadersFrame
      # Create new frame without pooling for now
      HeadersFrame.new(stream_id, header_block, flags)
    end

    def release(frame : Frame) : Nil
      # No-op since we're not pooling frames yet
    end
  end

  # Global frame pool manager
  @@frame_pool_manager : FramePoolManager? = nil

  def self.frame_pools : FramePoolManager
    @@frame_pool_manager ||= FramePoolManager.new
  end

  def self.frame_pools=(manager : FramePoolManager) : FramePoolManager
    @@frame_pool_manager = manager
  end
end
