require "../spec_helper"

describe "H2O::TlsSocket integration", tags: "integration" do

  describe "#initialize" do
    it "creates TLS socket with default verify mode" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      socket.should_not be_nil
      socket.close
    end

    it "creates TLS socket with custom verify mode" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      socket.should_not be_nil
      socket.close
    end

    it "sets ALPN protocol to h2" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      # After connection, ALPN should be negotiated
      socket.alpn_protocol.should eq("h2")
      socket.close
    end
  end

  describe "#alpn_protocol" do
    it "returns h2 when connected to HTTP/2 server" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      socket.alpn_protocol.should eq("h2")
      socket.close
    end
  end

  describe "#negotiated_http2?" do
    it "returns true when ALPN protocol is h2" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      socket.negotiated_http2?.should be_true
      socket.close
    end
  end

  describe "socket operations" do
    it "provides read and write methods" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)

      # Write HTTP/2 preface
      preface = H2O::Preface::CONNECTION_PREFACE
      bytes_written = socket.write(preface)
      socket.flush
      bytes_written.should eq(preface.size)

      socket.flush

      # Read response
      buffer = Bytes.new(100)
      bytes_read = socket.read(buffer)
      bytes_read.should be > 0

      socket.close
    end

    it "provides close and closed? methods" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      socket.closed?.should be_false

      socket.close
      socket.closed?.should be_true
    end

    it "provides to_io method" do
      socket = H2O::TlsSocket.new("nghttpd", 4430, OpenSSL::SSL::VerifyMode::NONE)
      io = socket.to_io
      io.should be_a(IO)
      socket.close
    end
  end

  describe "error handling" do
    it "handles connection failures gracefully" do
      expect_raises(IO::Error, /Failed to connect/) do
        H2O::TlsSocket.new("nghttpd", 9999, connect_timeout: 1.seconds)
      end
    end

    it "handles invalid hostnames" do
      expect_raises(IO::Error) do
        H2O::TlsSocket.new("invalid.nonexistent.host", 4430, connect_timeout: 1.seconds)
      end
    end
  end
end
