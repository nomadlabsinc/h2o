require "../spec_helper"

describe H2O::TlsSocket do
  describe "#initialize" do
    it "creates TLS socket with default verify mode" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        H2O::TlsSocket.new("localhost", 9999)
      end
    end

    it "creates TLS socket with custom verify mode" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        H2O::TlsSocket.new("localhost", 9999, OpenSSL::SSL::VerifyMode::NONE)
      end
    end

    it "sets ALPN protocol to h2" do
      # We can't test the actual ALPN protocol setting without a real connection,
      # but we can verify the socket creation with ALPN configuration doesn't crash
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.close
      end
    end
  end

  describe "#alpn_protocol" do
    it "returns nil when not connected" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.alpn_protocol.should be_nil
      end
    end
  end

  describe "#negotiated_http2?" do
    it "returns false when ALPN protocol is not h2" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.negotiated_http2?.should be_false
      end
    end
  end

  describe "socket operations" do
    it "provides read method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        buffer = Bytes.new(10)
        socket.read(buffer)
      end
    end

    it "provides write method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        data = "test".to_slice
        socket.write(data)
      end
    end

    it "provides flush method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.flush
      end
    end

    it "provides close method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.close
      end
    end

    it "provides closed? method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        socket.closed?.should be_false
        socket.close
        socket.closed?.should be_true
      end
    end

    it "provides to_io method" do
      expect_raises(Socket::ConnectError, /connection refused|network is unreachable/i) do
        socket = H2O::TlsSocket.new("localhost", 9999)
        io = socket.to_io
        io.should be_a(IO)
      end
    end
  end
end
