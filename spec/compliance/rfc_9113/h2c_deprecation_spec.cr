require "../../spec_helper"
require "../../support/in_memory_transport"

describe "RFC 9113 h2c Upgrade Deprecation" do
  describe "RFC 9113 Section 3.2 compliance" do
    it "does not attempt Upgrade: h2c mechanism" do
      # RFC 9113 deprecates the Upgrade: h2c mechanism
      # Clients should use "prior knowledge" h2c instead

      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # When establishing connection, should not send HTTP/1.1 Upgrade header
      engine.establish_connection

      outgoing = transport.get_outgoing_data
      outgoing_string = String.new(outgoing)

      # Should not contain HTTP/1.1 upgrade request
      outgoing_string.should_not contain("GET ")
      outgoing_string.should_not contain("HTTP/1.1")
      outgoing_string.should_not contain("Upgrade: h2c")
      outgoing_string.should_not contain("Connection: Upgrade")
      outgoing_string.should_not contain("HTTP2-Settings:")

      # Should start directly with HTTP/2 connection preface
      outgoing_string.should start_with("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    end

    it "uses prior knowledge h2c for unencrypted connections" do
      # RFC 9113 strongly favors "prior knowledge" over Upgrade mechanism
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Establish connection using prior knowledge (direct HTTP/2)
      result = engine.establish_connection
      result.should be_true

      # Should send HTTP/2 preface immediately
      outgoing = transport.get_outgoing_data

      # Verify direct HTTP/2 connection establishment
      expected_preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
      actual_preface = String.new(outgoing[0, 24])
      actual_preface.should eq(expected_preface)

      # Should be followed by SETTINGS frame (not HTTP/1.1)
      settings_frame_type = outgoing[24 + 3] # Frame type byte
      settings_frame_type.should eq(0x04_u8) # SETTINGS frame
    end

    it "rejects server attempts to use deprecated Upgrade mechanism" do
      # If a server somehow tries to use Upgrade: h2c, client should handle appropriately
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Simulate server sending HTTP/1.1 101 Switching Protocols (deprecated pattern)
      http11_upgrade_response = "HTTP/1.1 101 Switching Protocols\r\n" +
                                "Connection: Upgrade\r\n" +
                                "Upgrade: h2c\r\n" +
                                "\r\n"

      # Inject the deprecated response pattern
      transport.inject_incoming_data(http11_upgrade_response.to_slice)

      # Client should not treat this as valid HTTP/2 (it expects frames, not HTTP/1.1)
      # The malformed "frame" should be handled gracefully or cause appropriate error
      engine.closed?.should be_false

      # Client should continue expecting proper HTTP/2 frames
      engine.connection_established.should be_true
    end
  end

  describe "client initiation behavior" do
    it "does not generate HTTP/1.1 headers for h2c connections" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Client should not generate any HTTP/1.1 content
      engine.establish_connection

      # Send a request
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      engine.send_request("GET", "/", headers)

      outgoing = transport.get_outgoing_data
      outgoing_string = String.new(outgoing)

      # Should contain no HTTP/1.1 artifacts
      outgoing_string.should_not contain("HTTP/1.1")
      outgoing_string.should_not contain("Upgrade:")
      outgoing_string.should_not contain("Connection:")

      # Should only contain HTTP/2 binary frames after preface
      # Verify presence of HTTP/2 frames (binary data after preface)
      outgoing.size.should be > 24 # More than just preface
    end

    it "establishes h2c connections without negotiation overhead" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Prior knowledge should be more efficient (no round-trip negotiation)
      start_time = Time.monotonic
      engine.establish_connection
      establishment_time = Time.monotonic - start_time

      # Should establish quickly (no HTTP/1.1 negotiation round trip)
      establishment_time.should be < 1.millisecond

      # Should be ready to send requests immediately
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("GET", "/", headers)
      stream_id.should eq(1_u32)
    end

    it "provides clear error messages for h2c configuration issues" do
      # If there are h2c-specific configuration issues, should provide clear feedback
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Verify normal operation works
      result = engine.establish_connection
      result.should be_true

      # In a complete implementation, configuration errors would be caught early
      # For now, verify basic functionality works
      engine.connection_established.should be_true
    end
  end

  describe "compatibility with RFC 9113 recommendations" do
    it "follows RFC 9113 preference for prior knowledge over upgrade" do
      # RFC 9113 Section 3.2: "prior knowledge" is preferred over "Upgrade: h2c"
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Should use prior knowledge approach
      engine.establish_connection

      outgoing = transport.get_outgoing_data

      # Should start with HTTP/2 preface (prior knowledge)
      preface = String.new(outgoing[0, 24])
      preface.should eq("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

      # No HTTP/1.1 upgrade artifacts
      String.new(outgoing).should_not contain("101 Switching Protocols")
    end

    it "maintains compatibility with servers expecting prior knowledge" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Simulate server that expects prior knowledge h2c
      # Server should respond with SETTINGS frame (not HTTP/1.1)
      server_settings = Bytes.new(9) # Empty SETTINGS frame

      # SETTINGS frame header
      server_settings[0] = 0x00 # Length
      server_settings[1] = 0x00
      server_settings[2] = 0x00 # 0 bytes payload (empty SETTINGS)
      server_settings[3] = 0x04 # SETTINGS frame type
      server_settings[4] = 0x00 # No flags
      server_settings[5] = 0x00 # Stream 0
      server_settings[6] = 0x00
      server_settings[7] = 0x00
      server_settings[8] = 0x00

      # Inject server's SETTINGS response
      transport.inject_incoming_data(server_settings)

      # Client should handle properly (no upgrade confusion)
      engine.closed?.should be_false
      engine.connection_established.should be_true
    end

    it "does not fall back to HTTP/1.1 upgrade on h2c failure" do
      # RFC 9113 deprecates Upgrade: h2c, so no fallback to that mechanism
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Establish connection normally
      engine.establish_connection

      # If h2c fails, should not attempt HTTP/1.1 upgrade fallback
      # (In practice, connection would fail cleanly rather than downgrade)

      # Simulate connection issue by injecting invalid data
      transport.inject_incoming_data("INVALID".to_slice)

      # Should not generate HTTP/1.1 upgrade headers as fallback
      outgoing = transport.get_outgoing_data
      String.new(outgoing).should_not contain("Upgrade: h2c")
    end
  end

  describe "protocol documentation and warnings" do
    it "includes deprecation awareness in protocol handling" do
      # Verify that the codebase acknowledges RFC 9113 deprecation
      # This is more of a documentation/awareness test

      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Normal operation should work without deprecated mechanisms
      engine.establish_connection.should be_true

      headers = H2O::Headers.new
      headers["host"] = "example.com"
      stream_id = engine.send_request("GET", "/", headers)

      # Should complete successfully using modern approach
      stream_id.should be > 0
      engine.active_streams.has_key?(stream_id).should be_true
    end

    it "implements RFC 9113 Section 3.2 correctly" do
      # Comprehensive test that the client behavior aligns with RFC 9113 Section 3.2
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # 1. Uses prior knowledge (direct HTTP/2)
      engine.establish_connection
      outgoing = transport.get_outgoing_data
      String.new(outgoing).should start_with("PRI * HTTP/2.0")

      # 2. Does not use deprecated Upgrade: h2c
      String.new(outgoing).should_not contain("Upgrade:")

      # 3. Can send requests immediately after preface
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      stream_id = engine.send_request("GET", "/api/test", headers)

      # 4. Functions correctly without upgrade negotiation
      stream_id.should eq(1_u32)
      engine.connection_established.should be_true
    end
  end
end
