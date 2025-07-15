module H2O
  # Reference-counted buffer for zero-copy frame processing
  # Ensures buffer lifetime management while allowing slice views
  class PooledBuffer
    # Atomic reference counter for fiber-safe operations
    @ref_count : Atomic(Int32)
    @buffer : Bytes
    @pool_return_proc : Proc(Bytes, Nil)?
    
    def initialize(@buffer : Bytes, @pool_return_proc : Proc(Bytes, Nil)? = nil)
      @ref_count = Atomic(Int32).new(1) # Start with 1 reference
    end
    
    # Get a slice view of the buffer
    def slice(offset : Int32, count : Int32) : Slice(UInt8)
      if offset < 0 || count < 0 || offset + count > @buffer.size
        raise IndexError.new("Buffer slice out of bounds: offset=#{offset}, count=#{count}, buffer_size=#{@buffer.size}")
      end
      
      @buffer[offset, count]
    end
    
    # Get the full buffer as a slice
    def to_slice : Slice(UInt8)
      @buffer.to_slice
    end
    
    # Retain the buffer (increment reference count)
    def retain : PooledBuffer
      @ref_count.add(1)
      self
    end
    
    # Release the buffer (decrement reference count)
    # Returns true if buffer was actually returned to pool
    def release : Bool
      new_count = @ref_count.sub(1)
      
      if new_count == 0
        # Last reference released - return to pool
        if pool_proc = @pool_return_proc
          pool_proc.call(@buffer)
        end
        true
      elsif new_count < 0
        # This should never happen in correct usage
        raise RuntimeError.new("PooledBuffer reference count went negative: #{new_count}")
      else
        false
      end
    end
    
    # Get current reference count (for debugging/testing)
    def ref_count : Int32
      @ref_count.get
    end
    
    # Get buffer size
    def size : Int32
      @buffer.size
    end
    
    # Check if buffer is empty
    def empty? : Bool
      @buffer.empty?
    end
  end
  
  # Factory for creating pooled buffers with automatic pool return
  module PooledBufferFactory
    extend self
    
    # Create a pooled buffer from a raw buffer with pool return callback
    def create_from_pool(buffer : Bytes, return_proc : Proc(Bytes, Nil)) : PooledBuffer
      PooledBuffer.new(buffer, return_proc)
    end
    
    # Create a pooled buffer without pool return (for non-pooled buffers)  
    def create_non_pooled(buffer : Bytes) : PooledBuffer
      PooledBuffer.new(buffer, nil)
    end
    
    # Create a pooled buffer using the buffer pool system
    def create_for_frame_reading(size : Int32) : PooledBuffer
      if ENV.fetch("H2O_DISABLE_BUFFER_POOLING", "false") == "true"
        # Use direct allocation when pooling is disabled
        buffer = Bytes.new(size)
        create_non_pooled(buffer)
      else
        # Use buffer pool with automatic return
        if size <= BufferPool::LARGE_BUFFER_SIZE
          buffer = BufferPool.get_header_buffer
          return_proc = ->(buf : Bytes) { BufferPool.return_header_buffer(buf) }
        else
          buffer = BufferPool.get_frame_buffer(size)
          return_proc = ->(buf : Bytes) { BufferPool.return_frame_buffer(buf) }
        end
        
        create_from_pool(buffer, return_proc)
      end
    end
  end
end