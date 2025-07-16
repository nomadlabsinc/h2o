require "../../src/h2o/io_adapter"

module H2O::Test
  # In-memory transport implementation for testing
  # Simulates byte streams using internal buffers
  class InMemoryTransport < IoAdapter
    # Internal buffers for incoming and outgoing data
    property incoming_buffer : IO::Memory
    property outgoing_buffer : IO::Memory
    property is_closed : Bool
    property mutex : Mutex
    
    # Callbacks for async notification
    property data_callback : (Bytes -> Nil)?
    property close_callback : (-> Nil)?
    
    def initialize
      @incoming_buffer = IO::Memory.new
      @outgoing_buffer = IO::Memory.new  
      @is_closed = false
      @mutex = Mutex.new
      @data_callback = nil
      @close_callback = nil
    end
    
    # Read bytes from incoming buffer (simulates network receive)
    def read_bytes(buffer_size : Int32) : Bytes?
      @mutex.synchronize do
        return nil if @is_closed || @incoming_buffer.size == 0
        
        # Read available data up to buffer_size
        available = [@incoming_buffer.size - @incoming_buffer.pos, buffer_size].min
        return nil if available <= 0
        
        bytes = Bytes.new(available)
        bytes_read = @incoming_buffer.read(bytes)
        return nil if bytes_read == 0
        
        # Return only the bytes actually read
        bytes[0, bytes_read]
      end
    end
    
    # Write bytes to outgoing buffer (simulates network send)
    def write_bytes(bytes : Bytes) : Int32
      @mutex.synchronize do
        return 0 if @is_closed
        
        @outgoing_buffer.write(bytes)
        bytes.size
      end
    end
    
    # Close the transport
    def close : Nil
      @mutex.synchronize do
        @is_closed = true
        @close_callback.try(&.call)
      end
    end
    
    # Check if transport is closed
    def closed? : Bool
      @mutex.synchronize { @is_closed }
    end
    
    # Register data available callback
    def on_data_available(&block : Bytes -> Nil) : Nil
      @data_callback = block
    end
    
    # Register connection closed callback
    def on_closed(&block : -> Nil) : Nil
      @close_callback = block
    end
    
    # Test helper: Inject incoming data (simulates receiving from network)
    def inject_incoming_data(data : Bytes) : Nil
      @mutex.synchronize do
        return if @is_closed
        
        @incoming_buffer.write(data)
        @incoming_buffer.rewind
        
        # Notify callback if registered
        @data_callback.try(&.call(data))
      end
    end
    
    # Test helper: Inject incoming data from string
    def inject_incoming_data(data : String) : Nil
      inject_incoming_data(data.to_slice)
    end
    
    # Test helper: Get all outgoing data written so far
    def get_outgoing_data : Bytes
      @mutex.synchronize do
        @outgoing_buffer.to_slice.dup
      end
    end
    
    # Test helper: Get outgoing data as string (for debugging)
    def get_outgoing_data_string : String
      String.new(get_outgoing_data)
    end
    
    # Test helper: Clear outgoing buffer
    def clear_outgoing_data : Nil
      @mutex.synchronize do
        @outgoing_buffer = IO::Memory.new
      end
    end
    
    # Test helper: Clear incoming buffer
    def clear_incoming_data : Nil
      @mutex.synchronize do
        @incoming_buffer = IO::Memory.new
      end
    end
    
    # Test helper: Simulate connection close from remote
    def simulate_remote_close : Nil
      close
    end
    
    # Test helper: Check if any data is available for reading
    def has_incoming_data? : Bool
      @mutex.synchronize do
        @incoming_buffer.size > @incoming_buffer.pos
      end
    end
    
    # Test helper: Check if any data has been written
    def has_outgoing_data? : Bool
      @mutex.synchronize do
        @outgoing_buffer.size > 0
      end
    end
    
    # Transport info for testing
    def transport_info : Hash(String, String)
      {
        "type" => "in_memory",
        "incoming_buffer_size" => @incoming_buffer.size.to_s,
        "outgoing_buffer_size" => @outgoing_buffer.size.to_s,
        "closed" => @is_closed.to_s
      }
    end
  end
end