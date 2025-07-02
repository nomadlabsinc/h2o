require "openssl"
require "./tls_cache"

module H2O
  class TlsSocket
    @socket : OpenSSL::SSL::Socket::Client?
    @tcp_socket : TCPSocket?
    @closed : Bool
    @hostname : String
    @port : Int32
    @cache_key : String
    @mutex : Mutex

    def initialize(hostname : String, port : Int32, verify_mode : OpenSSL::SSL::VerifyMode = OpenSSL::SSL::VerifyMode::PEER, connect_timeout : Time::Span = 5.seconds)
      @hostname = hostname
      @port = port
      @cache_key = "#{hostname}:#{port}"
      @mutex = Mutex.new
      @closed = false
      @tcp_socket = nil

      # Use timeout for initial TCP connection
      tcp_socket = begin
        channel = Channel(TCPSocket?).new(1)
        fiber = spawn do
          begin
            socket = TCPSocket.new(hostname, port)
            channel.send(socket)
          rescue ex
            channel.send(nil)
          end
        end

        begin
          select
          when socket = channel.receive
            raise IO::Error.new("Failed to connect to #{hostname}:#{port}") unless socket
            socket
          when timeout(connect_timeout)
            # Close the channel to prevent fiber leak
            channel.close
            raise IO::TimeoutError.new("Connection timeout to #{hostname}:#{port}")
          end
        ensure
          # Ensure channel is closed and fiber terminates
          channel.close rescue nil
        end
      end

      # Store TCP socket reference for proper cleanup
      @tcp_socket = tcp_socket

      # Create SSL context with proper error handling
      context = OpenSSL::SSL::Context::Client.new
      begin
        context.verify_mode = verify_mode
        context.alpn_protocol = "h2"

        # Direct SNI assignment - no global cache to avoid malloc corruption
        sni_name = hostname

        # Enable session caching if supported
        # Note: Crystal's OpenSSL bindings may have limited session support
        # This is a placeholder for future enhancement

        @socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: sni_name)

        # SNI caching disabled to avoid malloc corruption
        # H2O.tls_cache.set_sni(hostname, sni_name) if sni_name == hostname
      rescue ex
        # Ensure TCP socket is closed on SSL failure
        tcp_socket.close rescue nil
        @tcp_socket = nil
        raise ex
      end
    end

    def alpn_protocol : String?
      @mutex.synchronize do
        socket = @socket
        return nil if @closed || !socket
        socket.alpn_protocol
      end
    end

    def negotiated_http2? : Bool
      alpn_protocol == "h2"
    end

    def negotiated_http11? : Bool
      alpn_protocol == "http/1.1" || alpn_protocol.nil?
    end

    def read(slice : Bytes) : Int32
      @mutex.synchronize do
        socket = @socket
        raise IO::Error.new("Socket is closed") if @closed || !socket
        socket.read(slice)
      end
    end

    def write(slice : Bytes) : Int32
      @mutex.synchronize do
        socket = @socket
        raise IO::Error.new("Socket is closed") if @closed || !socket
        socket.write(slice)
        slice.size
      end
    end

    def flush : Nil
      @mutex.synchronize do
        socket = @socket
        return if @closed || !socket
        socket.flush
      end
    end

    def close : Nil
      @mutex.synchronize do
        return if @closed
        @closed = true

        # Close SSL socket first
        if socket = @socket
          @socket = nil
          begin
            socket.close unless socket.closed?
          rescue ex : Exception
            Log.debug { "Error closing SSL socket: #{ex.message}" }
          end
        end

        # Then close TCP socket
        if tcp_socket = @tcp_socket
          @tcp_socket = nil
          begin
            tcp_socket.close unless tcp_socket.closed?
          rescue ex : Exception
            Log.debug { "Error closing TCP socket: #{ex.message}" }
          end
        end

        # Small delay to allow OpenSSL cleanup
        sleep 1.millisecond
      end
    end

    def closed? : Bool
      @mutex.synchronize do
        @closed || @socket.nil?
      end
    end

    def to_io : IO
      @mutex.synchronize do
        socket = @socket
        raise IO::Error.new("Socket is closed") if @closed || !socket
        socket
      end
    end

    # Ensure cleanup on GC
    def finalize
      close rescue nil
    end
  end
end
