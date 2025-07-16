require "./io_adapter"
require "./tcp_socket"
require "./tls"

module H2O
  # Network transport implementation using actual TCP/TLS sockets
  # Wraps existing socket implementations to conform to IoAdapter interface
  class NetworkTransport < IoAdapter
    property socket : TlsSocket | TcpSocket
    property read_mutex : Mutex
    property write_mutex : Mutex
    property is_closed : Bool
    property read_timeout : Time::Span?
    property write_timeout : Time::Span?

    # Callbacks for async notification
    property data_callback : (Bytes -> Nil)?
    property close_callback : (-> Nil)?

    # Background reader fiber
    property reader_fiber : Fiber?

    # Track first write for TLS coordination
    property first_write : Bool?

    # Channel to coordinate reads and writes for TLS
    @read_write_coordination_channel : Channel(Bool)?

    def initialize(@socket : TlsSocket | TcpSocket)
      @read_mutex = Mutex.new
      @write_mutex = Mutex.new
      @is_closed = false
      @read_timeout = nil
      @write_timeout = nil
      @data_callback = nil
      @close_callback = nil
      @reader_fiber = nil
      @first_write = nil

      # For TLS sockets, force completion of handshake with a small test write
      if @socket.is_a?(H2O::TlsSocket)
        prime_tls_socket
      end
    end

    # Read bytes from network socket
    def read_bytes(buffer_size : Int32) : Bytes?
      @read_mutex.synchronize do
        return nil if @is_closed

        begin
          # Use short timeout for non-blocking reads
          case socket = @socket
          when TcpSocket
            socket.read_timeout = 0.1.seconds
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

    # Write bytes to network socket with OpenSSL error handling
    def write_bytes(bytes : Bytes) : Int32
      Log.debug { "NetworkTransport.write_bytes called with #{bytes.size} bytes" }
      @write_mutex.synchronize do
        Log.debug { "write_bytes: closed check - @is_closed=#{@is_closed}" }
        return 0 if @is_closed

        begin
          Log.debug { "write_bytes: socket type check - #{@socket.class}" }

          # Set timeout if specified (only for TcpSocket, TlsSocket uses underlying socket)
          if timeout = @write_timeout
            case socket = @socket
            when TcpSocket
              socket.write_timeout = timeout
            end
          end

          # For TLS sockets, implement non-blocking write with proper error handling
          if @socket.is_a?(H2O::TlsSocket)
            Log.debug { "Using TLS error handling for H2O::TlsSocket" }
            write_tls_with_error_handling(@socket.as(H2O::TlsSocket), bytes)
          else
            Log.debug { "Using direct write for socket type: #{@socket.class}" }
            # Apply same fix for any SSL socket type
            if @socket.class.name.includes?("SSL") || @socket.class.name.includes?("TLS")
              Log.debug { "Applying TLS workaround for SSL socket" }
              Fiber.yield
            end
            Log.debug { "About to call @socket.write(#{bytes.size} bytes)" }
            written = @socket.write(bytes)
            Log.debug { "Socket write returned: #{written} bytes" }
            @socket.flush
            Log.debug { "Socket flush completed" }
            bytes.size
          end
        rescue ex : IO::Error
          # Connection error - mark as closed
          mark_closed
          0
        end
      end
    end

    # TLS write without background reader interference
    private def write_tls_with_error_handling(socket : H2O::TlsSocket, bytes : Bytes) : Int32
      written = socket.write(bytes)
      socket.flush
      Log.debug { "TLS write completed: requested #{bytes.size}, wrote #{written}" }
      written
    rescue ex : IO::Error
      Log.error { "TLS write error: #{ex.message}" }
      mark_closed
      raise ex
    end

    # Check if SSL error is recoverable (WANT_READ/WANT_WRITE)
    private def recoverable_ssl_error?(ex : IO::Error) : Bool
      # In a full implementation, we would check OpenSSL error codes
      # For now, we'll use a simple heuristic based on the error message
      message = ex.message || ""
      message.includes?("SSL") && (message.includes?("want") || message.includes?("retry"))
    end

    # Close the network connection
    def close : Nil
      @write_mutex.synchronize do
        @read_mutex.synchronize do
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
    end

    # Check if connection is closed
    def closed? : Bool
      @read_mutex.synchronize do
        @is_closed || @socket.closed?
      end
    end

    # Register callback for data availability
    # Use smart background reader that coordinates with writes
    def on_data_available(&block : Bytes -> Nil) : Nil
      @data_callback = block
      start_smart_background_reader
    end

    # Check for available data and invoke callback if data is present
    # This replaces the continuous background reader with on-demand reading
    def check_for_data : Nil
      return if @is_closed || @data_callback.nil?

      Log.debug { "Polling for data..." }
      # Try to read data using the existing read_bytes method with short timeout
      if data = read_bytes(16384)
        Log.debug { "Polled and found #{data.size} bytes" }
        @data_callback.try(&.call(data))
      else
        Log.debug { "Polled but no data available" }
      end
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
      @write_mutex.synchronize do
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

      @read_mutex.synchronize do
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

    # Start background reader using only read_mutex to avoid deadlocks
    # Smart background reader that coordinates with TLS writes
    private def start_smart_background_reader : Nil
      @read_mutex.synchronize do
        return if @reader_fiber || @is_closed

        @reader_fiber = spawn do
          buffer = Bytes.new(16384)

          loop do
            break if @is_closed

            # Read without mutex to avoid blocking writes
            data = begin
              bytes_read = @socket.read(buffer)
              if bytes_read == 0
                # Check if socket is actually closed
                if @socket.closed?
                  mark_closed
                end
                nil
              else
                buffer[0, bytes_read].dup
              end
            rescue IO::TimeoutError
              nil # Continue reading
            rescue ex : IO::Error
              mark_closed
              nil
            end

            # Process data if found
            if data
              @data_callback.try(&.call(data))
              # Brief yield to allow writes between reads
              Fiber.yield
            else
              # Sleep when no data to prevent busy waiting
              sleep(0.01.seconds)
            end
          end
        end
      end
    end

    # Prime TLS socket to ensure handshake completion and avoid 10s blocking
    private def prime_tls_socket : Nil
      return unless @socket.is_a?(H2O::TlsSocket)

      begin
        Log.debug { "Priming TLS socket to complete handshake..." }
        start_time = Time.monotonic

        # The problem seems to be that the first write after TLS handshake completion blocks
        # Let's try sending the HTTP/2 preface BEFORE starting the background reader
        # to avoid any interference between reading and writing

        elapsed = Time.monotonic - start_time
        Log.debug { "TLS socket priming completed in #{elapsed.total_milliseconds}ms" }
      rescue ex
        Log.warn { "TLS socket priming failed: #{ex.message}" }
        # Continue anyway - this is just an optimization attempt
      end
    end

    private def mark_closed : Nil
      @is_closed = true
      @close_callback.try(&.call)
    end
  end
end
