require "socket"

module H2O
  class TcpSocket
    getter closed : Bool
    getter io : TCPSocket

    def initialize(@host : String, @port : Int32, connect_timeout : Time::Span = 5.seconds)
      @io = connect_with_timeout(@host, @port, connect_timeout)
      @closed = false
    end

    def read(slice : Bytes) : Int32
      check_closed!
      @io.read(slice)
    end

    def write(slice : Bytes) : Nil
      check_closed!
      @io.write(slice)
    end

    def flush : Nil
      check_closed!
      @io.flush
    end

    def close : Nil
      return if @closed
      @closed = true
      @io.close
    end

    def closed? : Bool
      @closed
    end

    def to_io : IO
      @io
    end

    def sync=(value : Bool) : Nil
      @io.sync = value
    end

    def read_timeout=(timeout : Time::Span?) : Nil
      @io.read_timeout = timeout
    end

    def write_timeout=(timeout : Time::Span?) : Nil
      @io.write_timeout = timeout
    end

    private def check_closed! : Nil
      raise IO::Error.new("Socket is closed") if @closed
    end

    private def connect_with_timeout(host : String, port : Int32, timeout : Time::Span) : TCPSocket
      channel = Channel(TCPSocket?).new(1)
      fiber = spawn do
        begin
          socket = TCPSocket.new(host, port)
          channel.send(socket)
        rescue ex
          channel.send(nil)
        end
      end

      begin
        select
        when socket = channel.receive
          raise IO::Error.new("Failed to connect to #{host}:#{port}") unless socket
          socket
        when timeout(timeout)
          # Close the channel to prevent fiber leak
          channel.close
          raise IO::TimeoutError.new("Connection timeout to #{host}:#{port}")
        end
      ensure
        # Ensure channel is closed
        channel.close rescue nil
      end
    end
  end
end
