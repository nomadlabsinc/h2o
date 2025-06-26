module H2O
  # Generic object pool for reducing allocations
  class ObjectPool(T)
    property available : Array(T)
    property capacity : Int32
    property created : Int32
    property factory : Proc(T)
    property reset : Proc(T, Nil)?
    property mutex : Mutex

    def initialize(@capacity : Int32, @factory : Proc(T), @reset : Proc(T, Nil)? = nil)
      @available = Array(T).new(@capacity)
      @created = 0
      @mutex = Mutex.new
    end

    def acquire : T
      @mutex.synchronize do
        if @available.empty?
          if @created < @capacity
            @created += 1
            @factory.call
          else
            # Pool exhausted, create new instance (will be GC'd)
            @factory.call
          end
        else
          @available.pop
        end
      end
    end

    def release(item : T) : Nil
      @mutex.synchronize do
        if @available.size < @capacity
          # Reset the object if reset proc provided
          @reset.try(&.call(item))
          @available << item
        end
        # If pool is full, let the object be GC'd
      end
    end

    def size : Int32
      @mutex.synchronize { @available.size }
    end

    def clear : Nil
      @mutex.synchronize do
        @available.clear
        @created = 0
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

    def acquire(stream_id : UInt32) : Stream
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

    def self.get_stream(stream_id : UInt32) : Stream
      instance.acquire(stream_id)
    end

    def self.release_stream(stream : Stream) : Nil
      instance.release(stream)
    end
  end

  # Frame object pools for different frame types
  class FramePoolManager
    property data_frame_pool : ObjectPool(DataFrame)
    property headers_frame_pool : ObjectPool(HeadersFrame)
    property settings_frame_pool : ObjectPool(SettingsFrame)
    property window_update_pool : ObjectPool(WindowUpdateFrame)

    def initialize(capacity : Int32 = 500)
      # DataFrame pool
      @data_frame_pool = ObjectPool(DataFrame).new(
        capacity,
        -> { DataFrame.new(1_u32, Bytes.empty, 0_u8) }, # Use temporary non-zero ID
        ->(frame : DataFrame) do
        frame.reset_for_reuse
        nil
      end
      )

      # HeadersFrame pool
      @headers_frame_pool = ObjectPool(HeadersFrame).new(
        capacity,
        -> { HeadersFrame.new(1_u32, Bytes.empty, 0_u8) }, # Use temporary non-zero ID
        ->(frame : HeadersFrame) do
        frame.reset_for_reuse
        nil
      end
      )

      # SettingsFrame pool
      @settings_frame_pool = ObjectPool(SettingsFrame).new(
        capacity // 10, # Settings frames are less frequent
        -> { SettingsFrame.new },
        ->(frame : SettingsFrame) do
          frame.reset_for_reuse
          nil
        end
      )

      # WindowUpdateFrame pool
      @window_update_pool = ObjectPool(WindowUpdateFrame).new(
        capacity // 2,
        -> { WindowUpdateFrame.new(0_u32, 1_u32) }, # Non-zero increment
        ->(frame : WindowUpdateFrame) do
        frame.reset_for_reuse
        nil
      end
      )
    end

    def acquire_data_frame(stream_id : UInt32, data : Bytes, flags : UInt8) : DataFrame
      frame = @data_frame_pool.acquire
      # Set stream_id before any other operations
      frame.stream_id = stream_id
      frame.flags = flags
      frame.set_data(data)
      frame
    end

    def acquire_headers_frame(stream_id : UInt32, header_block : Bytes, flags : UInt8) : HeadersFrame
      frame = @headers_frame_pool.acquire
      # Set stream_id before any other operations
      frame.stream_id = stream_id
      frame.flags = flags
      frame.set_header_block(header_block)
      frame
    end

    def release(frame : Frame) : Nil
      case frame
      when DataFrame
        @data_frame_pool.release(frame)
      when HeadersFrame
        @headers_frame_pool.release(frame)
      when SettingsFrame
        @settings_frame_pool.release(frame)
      when WindowUpdateFrame
        @window_update_pool.release(frame)
      else
        # Other frame types not pooled
      end
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
