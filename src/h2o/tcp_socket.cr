require "socket"

module H2O
  class TcpSocket
    getter closed : Bool
    getter io : TCPSocket

    def initialize(@host : String, @port : Int32)
      @io = TCPSocket.new(@host, @port)
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
  end
end
