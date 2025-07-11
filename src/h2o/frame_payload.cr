module H2O
  # Zero-copy frame payload that uses slices instead of copying data
  # Maintains reference to underlying pooled buffer for proper lifetime management
  struct ZeroCopyPayload
    @pooled_buffer : PooledBuffer?
    @slice : Slice(UInt8)
    
    # Create from a slice of a pooled buffer (zero-copy)
    def initialize(pooled_buffer : PooledBuffer, offset : Int32, count : Int32)
      @pooled_buffer = pooled_buffer
      @slice = pooled_buffer.slice(offset, count)
    end
    
    # Create from a direct slice (for non-pooled buffers)
    def initialize(@slice : Slice(UInt8))
      @pooled_buffer = nil
    end
    
    # Create from Bytes (compatibility mode - will copy)
    def initialize(bytes : Bytes)
      @slice = bytes.to_slice
      @pooled_buffer = nil
    end
    
    # Get the payload data as a slice
    def to_slice : Slice(UInt8)
      @slice
    end
    
    # Get the payload size
    def size : Int32
      @slice.size
    end
    
    # Check if payload is empty
    def empty? : Bool
      @slice.empty?
    end
    
    # Access individual bytes
    def [](index : Int32) : UInt8
      @slice[index]
    end
    
    # Get a sub-slice of the payload
    def [](offset : Int32, count : Int32) : Slice(UInt8)
      @slice[offset, count]
    end
    
    # Convert to Bytes (creates a copy - use sparingly)
    def to_bytes : Bytes
      Bytes.new(@slice.size) do |i|
        @slice[i]
      end
    end
    
    # Release the underlying buffer reference
    def release : Nil
      if pooled_buffer = @pooled_buffer
        pooled_buffer.release
        @pooled_buffer = nil
      end
    end
    
    # Create a sub-payload (retains buffer reference)
    def sub_payload(offset : Int32, count : Int32) : ZeroCopyPayload
      if offset < 0 || count < 0 || offset + count > @slice.size
        raise IndexError.new("Sub-payload out of bounds: offset=#{offset}, count=#{count}, payload_size=#{@slice.size}")
      end
      
      if pooled_buffer = @pooled_buffer
        # Create new payload with retained buffer reference
        pooled_buffer.retain
        ZeroCopyPayload.new(@slice[offset, count])
      else
        # Non-pooled buffer - just create slice
        ZeroCopyPayload.new(@slice[offset, count])
      end
    end
    
    # Check if this payload uses a pooled buffer
    def pooled? : Bool
      !@pooled_buffer.nil?
    end
  end
  
  # Factory methods for creating frame payloads
  module ZeroCopyPayloadFactory
    extend self
    
    # Create zero-copy payload from pooled buffer
    def from_pooled_buffer(buffer : PooledBuffer, offset : Int32 = 0, count : Int32? = nil) : ZeroCopyPayload
      actual_count = count || (buffer.size - offset)
      ZeroCopyPayload.new(buffer, offset, actual_count)
    end
    
    # Create payload from bytes (compatibility mode)
    def from_bytes(bytes : Bytes) : ZeroCopyPayload
      ZeroCopyPayload.new(bytes)
    end
    
    # Create empty payload
    def empty : ZeroCopyPayload
      ZeroCopyPayload.new(Bytes.empty)
    end
  end
end