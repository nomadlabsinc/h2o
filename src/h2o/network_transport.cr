require "./io_adapter"
require "./tcp_socket"
require "./tls"

module H2O
  # Network transport implementation using actual TCP/TLS sockets
  # Wraps existing socket implementations to conform to IoAdapter interface
  class NetworkTransport < IoAdapter
    property socket : TlsSocket | TcpSocket
    property mutex : Mutex
    property is_closed : Bool
    property read_timeout : Time::Span?
    property write_timeout : Time::Span?
    
    # Callbacks for async notification
    property data_callback : (Bytes -> Nil)?
    property close_callback : (-> Nil)?
    
    def initialize(@socket : TlsSocket | TcpSocket)
      @mutex = Mutex.new
      @is_closed = false
      @read_timeout = nil
      @write_timeout = nil
      @data_callback = nil
      @close_callback = nil
    end
    
    # Read bytes from network socket
    def read_bytes(buffer_size : Int32) : Bytes?
      @mutex.synchronize do
        return nil if @is_closed
        
        begin
          # Set timeout if specified (only for TcpSocket, TlsSocket uses underlying socket)
          if timeout = @read_timeout
            case socket = @socket
            when TcpSocket
              socket.read_timeout = timeout
            end
          end
          
          bytes = Bytes.new(buffer_size)
          bytes_read = @socket.read(bytes)
          
          return nil if bytes_read == 0
          
          # Return only the bytes actually read
          result = bytes[0, bytes_read]
          
          # Notify callback if registered
          @data_callback.try(&.call(result))
          
          result
        rescue IO::TimeoutError
          # Non-blocking behavior: return nil on timeout
          nil
        rescue ex : IO::Error
          # Connection error - mark as closed
          mark_closed
          nil
        end
      end
    end
    
    # Write bytes to network socket
    def write_bytes(bytes : Bytes) : Int32
      @mutex.synchronize do
        return 0 if @is_closed
        
        begin
          # Set timeout if specified (only for TcpSocket, TlsSocket uses underlying socket)
          if timeout = @write_timeout
            case socket = @socket
            when TcpSocket
              socket.write_timeout = timeout
            end
          end
          
          @socket.write(bytes)
          @socket.flush
          bytes.size
        rescue ex : IO::Error
          # Connection error - mark as closed
          mark_closed
          0
        end
      end
    end
    
    # Close the network connection
    def close : Nil
      @mutex.synchronize do
        return if @is_closed
        
        begin
          @socket.close
        rescue
          # Ignore errors during close
        ensure
          mark_closed
        end
      end
    end
    
    # Check if connection is closed
    def closed? : Bool
      @mutex.synchronize do
        @is_closed || @socket.closed?
      end
    end
    
    # Register callback for data availability
    # Note: For network sockets, this is typically handled by the event loop
    # This is a simplified implementation for compatibility
    def on_data_available(&block : Bytes -> Nil) : Nil
      @data_callback = block
    end
    
    # Register callback for connection closure
    def on_closed(&block : -> Nil) : Nil
      @close_callback = block
    end
    
    # Set read timeout
    def set_read_timeout(timeout : Time::Span) : Nil
      @read_timeout = timeout
    end
    
    # Set write timeout
    def set_write_timeout(timeout : Time::Span) : Nil
      @write_timeout = timeout
    end
    
    # Flush network socket
    def flush : Nil
      @mutex.synchronize do
        return if @is_closed
        
        begin
          @socket.flush
        rescue ex : IO::Error
          mark_closed
        end
      end
    end
    
    # Get network transport information
    def transport_info : Hash(String, String)
      info = Hash(String, String).new
      
      @mutex.synchronize do
        info["type"] = case @socket
                      when TlsSocket
                        "tls"
                      when TcpSocket
                        "tcp"
                      else
                        "unknown"
                      end
        
        info["closed"] = @is_closed.to_s
        
        # Add socket-specific information if available
        case socket = @socket
        when TlsSocket
          info["tls_version"] = socket.tls_version || "unknown"
          info["cipher"] = socket.cipher || "unknown"
          info["remote_address"] = socket.remote_address.to_s
        when TcpSocket
          info["remote_address"] = socket.remote_address.to_s
          info["local_address"] = socket.local_address.to_s
        end
      end
      
      info
    end
    
    # Helper method to get the underlying socket
    # Useful for operations that need direct socket access
    def underlying_socket : TlsSocket | TcpSocket
      @socket
    end
    
    private def mark_closed : Nil
      @is_closed = true
      @close_callback.try(&.call)
    end
  end
end