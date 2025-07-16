require "../../src/h2o/protocol_engine"
require "./in_memory_transport"

module H2O::Test
  # Helper methods for testing ProtocolEngine
  module ProtocolEngineTestHelper
    # Establish a complete HTTP/2 connection with handshake for testing
    def self.establish_test_connection(engine : H2O::ProtocolEngine, transport : InMemoryTransport) : Bool
      # Start connection establishment
      result = engine.establish_connection
      return false unless result
      
      # Give frame processing a moment to start
      sleep(0.01.seconds)
      
      # Simulate server SETTINGS frame (RFC 7540 format)
      # Frame: 9 bytes header + 6 bytes settings (HEADER_TABLE_SIZE = 4096)
      settings_frame = Bytes[
        0x00, 0x00, 0x06,  # Length: 6 bytes
        0x04,              # Type: SETTINGS (4)
        0x00,              # Flags: none
        0x00, 0x00, 0x00, 0x00,  # Stream ID: 0 (connection-level)
        # Settings payload: HEADER_TABLE_SIZE = 4096
        0x00, 0x01,        # Setting ID: HEADER_TABLE_SIZE (1)
        0x00, 0x00, 0x10, 0x00  # Setting Value: 4096
      ]
      
      # Inject the SETTINGS frame
      transport.inject_incoming_data(settings_frame)
      
      # Give frame processing time to handle the SETTINGS
      sleep(0.01.seconds)
      
      # Simulate server SETTINGS ACK frame
      settings_ack_frame = Bytes[
        0x00, 0x00, 0x00,  # Length: 0 bytes
        0x04,              # Type: SETTINGS (4)  
        0x01,              # Flags: ACK (0x01)
        0x00, 0x00, 0x00, 0x00  # Stream ID: 0
      ]
      
      # Inject the SETTINGS ACK
      transport.inject_incoming_data(settings_ack_frame)
      
      # Give final processing time
      sleep(0.02.seconds)
      
      # Check if connection is established
      engine.connection_established
    end
    
    # Simulate server SETTINGS frame for tests
    def self.send_server_settings(transport : InMemoryTransport) : Nil
      settings_frame = Bytes[
        0x00, 0x00, 0x06,  # Length: 6 bytes
        0x04,              # Type: SETTINGS (4)
        0x00,              # Flags: none
        0x00, 0x00, 0x00, 0x00,  # Stream ID: 0
        0x00, 0x01,        # HEADER_TABLE_SIZE (1)
        0x00, 0x00, 0x10, 0x00  # Value: 4096
      ]
      transport.inject_incoming_data(settings_frame)
      sleep(0.01.seconds)
    end
    
    # Simulate server SETTINGS ACK for tests
    def self.send_server_settings_ack(transport : InMemoryTransport) : Nil
      settings_ack_frame = Bytes[
        0x00, 0x00, 0x00,  # Length: 0
        0x04,              # Type: SETTINGS (4)
        0x01,              # Flags: ACK
        0x00, 0x00, 0x00, 0x00  # Stream ID: 0
      ]
      transport.inject_incoming_data(settings_ack_frame)
      sleep(0.01.seconds)
    end
  end
end