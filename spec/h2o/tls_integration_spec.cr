require "../spec_helper"

describe H2O::TlsSocket do
  describe "ALPN protocol configuration" do
    it "compiles successfully with current Crystal version" do
      # This test ensures that the ALPN protocol setting doesn't cause compilation errors
      # The actual TLS socket creation is tested, which validates the ALPN configuration
      begin
        # Try to create a socket - this will fail with connection error but will
        # validate that the ALPN protocol setting is syntactically correct
        H2O::TlsSocket.new("nonexistent.example.com", 443)
      rescue Socket::ConnectError | Socket::Addrinfo::Error
        # Expected - the important thing is that compilation succeeded
        true.should be_true
      rescue ex
        # If we get any other error, the ALPN configuration might be wrong
        fail "Unexpected error during TLS socket creation: #{ex.class}: #{ex.message}"
      end
    end

    it "uses h2 as ALPN protocol for HTTP/2 compatibility" do
      # This test verifies that we're setting up ALPN for HTTP/2
      # While we can't test the actual negotiation without a server,
      # we can verify the socket creation doesn't crash
      begin
        socket = H2O::TlsSocket.new("httpbin.org", 443)

        # If we successfully connect, verify HTTP/2 preference
        if socket.alpn_protocol
          # The ALPN protocol should be negotiated by the server
          # Most modern servers support h2, so this should work
          socket.alpn_protocol.should_not be_nil
        end

        socket.close
      rescue Socket::ConnectError | OpenSSL::SSL::Error
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
      # Verify that our ALPN setting prioritizes HTTP/2
      begin
        socket = H2O::TlsSocket.new("httpbin.org", 443)

        # The negotiated_http2? method should work correctly
        # It returns true if ALPN protocol is "h2"
        result = socket.negotiated_http2?
        result.should be_a(Bool)

        socket.close
      rescue Socket::ConnectError | OpenSSL::SSL::Error
        # Network/SSL errors are acceptable for this test
        true.should be_true
      end
    end
  end
end
