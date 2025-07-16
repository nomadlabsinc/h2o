require "../../spec_helper"
require "../../support/in_memory_transport"

describe "RFC 9113 Connection Preface Compliance" do
  describe "client connection preface" do
    it "sends correct 24-octet connection preface followed by SETTINGS" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Establish connection - this should send preface
      result = engine.establish_connection
      result.should be_true

      # Verify the outgoing data contains the correct preface
      outgoing = transport.get_outgoing_data
      outgoing.size.should be >= 24 # At least the preface

      # Check exact preface string (RFC 9113 Section 3.4)
      expected_preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
      actual_preface = String.new(outgoing[0, 24])
      actual_preface.should eq(expected_preface)

      # Verify SETTINGS frame follows the preface
      # Frame header is 9 bytes, starting at offset 24
      settings_frame_start = 24
      outgoing.size.should be >= settings_frame_start + 9

      # Check frame type (should be SETTINGS = 0x04)
      frame_type = outgoing[settings_frame_start + 3]
      frame_type.should eq(0x04_u8) # SETTINGS frame type
    end

    it "validates exact preface byte sequence per RFC 9113" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      engine.establish_connection
      outgoing = transport.get_outgoing_data

      # RFC 9113 Section 3.4: Connection preface must be exactly these 24 octets
      expected_bytes = [
        0x50, 0x52, 0x49, 0x20, 0x2a, 0x20, 0x48, 0x54, # "PRI * HT"
        0x54, 0x50, 0x2f, 0x32, 0x2e, 0x30, 0x0d, 0x0a, # "TP/2.0\r\n"
        0x0d, 0x0a, 0x53, 0x4d, 0x0d, 0x0a, 0x0d, 0x0a, # "\r\nSM\r\n\r\n"
      ]

      # Verify each byte of the preface
      expected_bytes.each_with_index do |expected_byte, index|
        outgoing[index].should eq(expected_byte.to_u8)
      end
    end

    it "sends initial SETTINGS frame after preface" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      engine.establish_connection
      outgoing = transport.get_outgoing_data

      # Skip past preface to SETTINGS frame
      settings_start = 24

      # Parse SETTINGS frame header
      length = (outgoing[settings_start].to_u32 << 16) |
               (outgoing[settings_start + 1].to_u32 << 8) |
               outgoing[settings_start + 2].to_u32
      frame_type = outgoing[settings_start + 3]
      flags = outgoing[settings_start + 4]
      stream_id = (outgoing[settings_start + 5].to_u32 << 24) |
                  (outgoing[settings_start + 6].to_u32 << 16) |
                  (outgoing[settings_start + 7].to_u32 << 8) |
                  outgoing[settings_start + 8].to_u32

      # Verify SETTINGS frame properties
      frame_type.should eq(0x04_u8) # SETTINGS
      stream_id.should eq(0_u32)    # Connection-level
      flags.should eq(0_u8)         # Not ACK
      length.should be > 0          # Should have some settings
    end
  end

  describe "preface error handling" do
    it "handles invalid server responses during preface validation" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Send invalid data as server response (simulating malformed server preface)
      transport.inject_incoming_data("INVALID SERVER RESPONSE")

      # This would be handled by the frame processing logic
      # For now, just verify the engine can handle unexpected data
      engine.establish_connection.should be_true

      # Engine should still be functional
      engine.closed?.should be_false
    end
  end

  describe "connection establishment flow" do
    it "follows RFC 9113 connection establishment sequence" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Step 1: Send connection preface and SETTINGS
      engine.establish_connection.should be_true

      # Step 2: Verify we can send requests after establishment
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("GET", "/", headers)
      stream_id.should eq(1_u32)

      # Step 3: Verify connection is considered established
      engine.connection_established.should be_true
    end

    it "prevents requests before connection establishment" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Try to send request without establishing connection
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      expect_raises(H2O::ConnectionError, /Connection not established/) do
        engine.send_request("GET", "/", headers)
      end
    end
  end
end
