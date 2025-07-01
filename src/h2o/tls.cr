require "openssl"
require "./tls_cache"

module H2O
  class TlsSocket
    @socket : OpenSSL::SSL::Socket::Client?
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
      # Use timeout for initial TCP connection
      tcp_socket = begin
        channel = Channel(TCPSocket?).new(1)
        spawn do
          begin
            socket = TCPSocket.new(hostname, port)
            channel.send(socket)
          rescue
            channel.send(nil)
          end
        end

        select
        when socket = channel.receive
          raise IO::Error.new("Failed to connect to #{hostname}:#{port}") unless socket
          socket
        when timeout(connect_timeout)
          raise IO::TimeoutError.new("Connection timeout to #{hostname}:#{port}")
        end
      end

      context = OpenSSL::SSL::Context::Client.new
      context.verify_mode = verify_mode
      context.alpn_protocol = "h2"

      # Check for cached SNI
      sni_name = H2O.tls_cache.get_sni(hostname) || hostname

      # Enable session caching if supported
      # Note: Crystal's OpenSSL bindings may have limited session support
      # This is a placeholder for future enhancement

      @socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: sni_name)
      @closed = false

      # Cache the SNI resolution
      H2O.tls_cache.set_sni(hostname, sni_name) if sni_name == hostname
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

        if socket = @socket
          begin
            # Ensure we only close once by setting closed immediately
            @closed = true
            @socket = nil

            # Use a more defensive approach to closing
            if !socket.closed?
              socket.close
            end
          rescue ex : Exception
            Log.debug { "Error closing SSL socket: #{ex.message}" }
          end
        else
          @closed = true
        end
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
  end
end
