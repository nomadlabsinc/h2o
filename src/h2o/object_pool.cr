module H2O
  # Generic object pool for reducing allocations using fiber-safe channels
  # Enhanced with memory safety features to prevent corruption
  class ObjectPool(T)
    property pool : Channel(T)
    property capacity : Int32
    property factory : Proc(T)
    property reset : Proc(T, Nil)?
    property validator : Proc(T, Bool)?
    property total_created : Int32
    property total_reused : Int32

    def initialize(@capacity : Int32, @factory : Proc(T), @reset : Proc(T, Nil)? = nil, @validator : Proc(T, Bool)? = nil)
      @pool = Channel(T).new(@capacity)
      @total_created = 0
      @total_reused = 0
    end

    def acquire : T
      # Try to get from pool first, otherwise create new
      select
      when item = @pool.receive
        # Validate item before reuse to prevent corruption
        if valid_item?(item)
          @total_reused += 1
          item
        else
          # Item is corrupted, create new one
          @total_created += 1
          @factory.call
        end
      else
        @total_created += 1
        @factory.call
      end
    end

    def release(item : T) : Nil
      # Validate item before reset to prevent corruption
      return unless valid_item?(item)

      # Reset the object if reset proc provided
      # Wrap in begin/rescue to prevent crashes from corrupted objects
      begin
        @reset.try(&.call(item))
      rescue
        # Reset failed, don't return to pool
        return
      end

      # Validate again after reset
      return unless valid_item?(item)

      # Try to return to pool, drop if full
      select
      when @pool.send(item)
        # Successfully returned to pool
      else
        # Pool is full, item will be garbage collected
      end
    end

    # Validate an item to ensure it's not corrupted
    private def valid_item?(item : T) : Bool
      return false if item.nil?

      # Use custom validator if provided
      if validator = @validator
        begin
          return validator.call(item)
        rescue
          return false
        end
      end

      # Default validation - just check if it's not nil
      true
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

    # Get pool statistics for monitoring
    def stats : Hash(String, Int32)
      {
        "total_created" => @total_created,
        "total_reused"  => @total_reused,
        "reuse_ratio"   => @total_created > 0 ? (@total_reused * 100) // @total_created : 0,
        "capacity"      => @capacity,
      }
    end

    # Reset statistics
    def reset_stats : Nil
      @total_created = 0
      @total_reused = 0
    end
  end

  # Simplified frame pool manager for stability
  # Frame pooling disabled for memory safety
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
