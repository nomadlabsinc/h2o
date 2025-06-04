require "openssl"

module H2O
  class TlsSocket
    @socket : OpenSSL::SSL::Socket::Client

    def initialize(hostname : String, port : Int32, verify_mode : OpenSSL::SSL::VerifyMode = OpenSSL::SSL::VerifyMode::PEER)
      tcp_socket = TCPSocket.new(hostname, port)
      context = OpenSSL::SSL::Context::Client.new
      context.verify_mode = verify_mode
      context.alpn_protocol = "h2"

      @socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: hostname)
    end

    def alpn_protocol : String?
      @socket.alpn_protocol
    end

    def negotiated_http2? : Bool
      alpn_protocol == "h2"
    end

    def read(slice : Bytes) : Int32
      @socket.read(slice)
    end

    def write(slice : Bytes) : Nil
      @socket.write(slice)
    end

    def flush : Nil
      @socket.flush
    end

    def close : Nil
      @socket.close
    end

    def closed? : Bool
      @socket.closed?
    end

    def to_io : IO
      @socket
    end
  end
end
