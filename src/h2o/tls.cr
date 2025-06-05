require "openssl"

module H2O
  class TlsSocket
    @socket : OpenSSL::SSL::Socket::Client?
    @closed : Bool

    def initialize(hostname : String, port : Int32, verify_mode : OpenSSL::SSL::VerifyMode = OpenSSL::SSL::VerifyMode::PEER, connect_timeout : Time::Span = 5.seconds)
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

      @socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: hostname)
      @closed = false
    end

    def alpn_protocol : String?
      socket = @socket
      return nil if @closed || !socket
      socket.alpn_protocol
    end

    def negotiated_http2? : Bool
      alpn_protocol == "h2"
    end

    def negotiated_http11? : Bool
      alpn_protocol == "http/1.1" || alpn_protocol.nil?
    end

    def read(slice : Bytes) : Int32
      socket = @socket
      raise IO::Error.new("Socket is closed") if @closed || !socket
      socket.read(slice)
    end

    def write(slice : Bytes) : Nil
      socket = @socket
      raise IO::Error.new("Socket is closed") if @closed || !socket
      socket.write(slice)
    end

    def flush : Nil
      socket = @socket
      return if @closed || !socket
      socket.flush
    end

    def close : Nil
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

    def closed? : Bool
      @closed || @socket.nil?
    end

    def to_io : IO
      socket = @socket
      raise IO::Error.new("Socket is closed") if @closed || !socket
      socket
    end
  end
end
