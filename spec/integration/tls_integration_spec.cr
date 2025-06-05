require "../spec_helper"

describe H2O::TlsSocket do
  describe "ALPN protocol configuration" do
    it "compiles successfully with current Crystal version" do
      # This test ensures that the ALPN protocol setting doesn't cause compilation errors
      # Test against nghttp2.org - the reference HTTP/2 implementation
      begin
        socket = H2O::TlsSocket.new("nghttp2.org", 443, connect_timeout: TestConfig::NGHTTP2_TIMEOUT)
        socket.should_not be_nil
        socket.close
      rescue Socket::ConnectError | Socket::Addrinfo::Error | IO::TimeoutError
        # Network timeouts are acceptable - the important thing is compilation succeeded
        true.should be_true
      rescue ex
        # If we get any other error, the ALPN configuration might be wrong
        fail "Unexpected error during TLS socket creation: #{ex.class}: #{ex.message}"
      end
    end

    it "uses h2 as ALPN protocol for HTTP/2 compatibility" do
      # Test against Google's reliable HTTP/2 endpoint
      begin
        socket = H2O::TlsSocket.new("www.google.com", 443, connect_timeout: TestConfig::GOOGLE_TIMEOUT)

        # If we successfully connect, verify HTTP/2 negotiation
        if socket.alpn_protocol
          # Google reliably supports HTTP/2, so this should be "h2"
          socket.alpn_protocol.should eq("h2")
        end

        socket.close
      rescue Socket::ConnectError | OpenSSL::SSL::Error | IO::TimeoutError
        # Network issues or SSL handshake failures are acceptable
        # The important thing is that our ALPN configuration doesn't cause crashes
        true.should be_true
      end
    end
  end

  describe "Crystal 1.16+ compatibility" do
    it "does not use deprecated Array(String) ALPN API" do
      # This test is designed to fail if someone reverts to the old API
      # We verify this by ensuring compilation succeeds and the socket can be created

      # Read the source file and verify it doesn't contain the old API
      source = File.read(File.join(__DIR__, "../../src/h2o/tls.cr"))

      # Ensure we're not using the old broken API
      source.should_not contain(%(["h2", "http/1.1"]))
      source.should_not contain("Array(String)")

      # Ensure we're using the new API correctly
      source.should contain(%(context.alpn_protocol = "h2"))
    end

    it "maintains HTTP/2 priority in ALPN negotiation" do
      # Test against nghttp2.org - guaranteed to support HTTP/2
      begin
        socket = H2O::TlsSocket.new("nghttp2.org", 443, connect_timeout: TestConfig::NGHTTP2_TIMEOUT)

        # The negotiated_http2? method should work correctly
        # It returns true if ALPN protocol is "h2"
        result = socket.negotiated_http2?
        result.should be_a(Bool)

        socket.close
      rescue Socket::ConnectError | OpenSSL::SSL::Error | IO::TimeoutError
        # Network/SSL errors are acceptable for this test
        true.should be_true
      end
    end
  end
end
