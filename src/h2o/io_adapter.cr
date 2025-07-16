module H2O
  # Abstract interface for I/O operations in HTTP/2 client
  # This enables separation of protocol logic from transport mechanism
  # allowing for both network and in-memory testing implementations
  abstract class IoAdapter
    # Read bytes from the transport layer
    # Returns nil if no data is immediately available (non-blocking)
    # Returns Bytes if data is available
    abstract def read_bytes(buffer_size : Int32) : Bytes?
    
    # Write bytes to the transport layer
    # Returns number of bytes actually written
    abstract def write_bytes(bytes : Bytes) : Int32
    
    # Close the transport connection
    abstract def close : Nil
    
    # Check if the transport is closed
    abstract def closed? : Bool
    
    # Register callback for when data becomes available
    # Used for asynchronous notification of incoming data
    abstract def on_data_available(&block : Bytes -> Nil) : Nil
    
    # Register callback for when connection is closed
    # Used for cleanup and error handling
    abstract def on_closed(&block : -> Nil) : Nil
    
    # Optional: Set timeout for read operations
    # Default implementation can be no-op for implementations that don't support timeouts
    def set_read_timeout(timeout : Time::Span) : Nil
      # Default implementation - override if needed
    end
    
    # Optional: Set timeout for write operations  
    # Default implementation can be no-op for implementations that don't support timeouts
    def set_write_timeout(timeout : Time::Span) : Nil
      # Default implementation - override if needed
    end
    
    # Flush any buffered data to the underlying transport
    # Default implementation can be no-op for unbuffered transports
    def flush : Nil
      # Default implementation - override if needed
    end
    
    # Get transport-specific information (e.g., remote address, TLS info)
    # Returns a hash with implementation-specific details
    def transport_info : Hash(String, String)
      Hash(String, String).new
    end
  end
end