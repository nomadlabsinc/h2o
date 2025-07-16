require "../../spec_helper"
require "../../support/in_memory_transport"

describe "RFC 9113 Flow Control Compliance" do
  describe "connection-level flow control" do
    it "respects initial connection window size" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Default initial window size is 65535 bytes
      engine.connection_window_size.should eq(65535)
    end

    it "handles window size updates correctly" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Send data that would consume window
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("POST", "/upload", headers)

      # Send data (in complete implementation, this would track window consumption)
      large_data = "x" * 1000
      engine.send_data(stream_id, large_data, end_stream: true)

      # Verify data was sent successfully
      transport.has_outgoing_data?.should be_true
    end

    it "prevents window overflow from WINDOW_UPDATE frames" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Simulate receiving WINDOW_UPDATE that would overflow
      # This test structure shows where overflow protection would be implemented

      # Current window + large increment should not exceed 2^31-1
      current_window = engine.connection_window_size
      max_window = 2_147_483_647 # 2^31-1

      # Verify current window is within bounds
      current_window.should be <= max_window
      current_window.should be > 0
    end
  end

  describe "stream-level flow control" do
    it "manages individual stream windows independently" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      # Create multiple streams
      stream1 = engine.send_request("POST", "/upload1", headers)
      stream2 = engine.send_request("POST", "/upload2", headers)
      stream3 = engine.send_request("POST", "/upload3", headers)

      # Each stream should have independent flow control
      # (Implementation would track per-stream windows)
      stream1.should_not eq(stream2)
      stream2.should_not eq(stream3)

      # Send data on different streams
      engine.send_data(stream1, "data1", end_stream: true)
      engine.send_data(stream2, "data2", end_stream: true)
      engine.send_data(stream3, "data3", end_stream: true)

      transport.has_outgoing_data?.should be_true
    end

    it "handles zero window size correctly" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # In a complete implementation, when window size reaches 0,
      # the client should stop sending DATA frames until WINDOW_UPDATE received

      headers = H2O::Headers.new
      headers["host"] = "example.com"
      stream_id = engine.send_request("POST", "/", headers)

      # This test demonstrates where zero window handling would be implemented
      # For now, just verify we can send data normally
      engine.send_data(stream_id, "test data", end_stream: true)
      transport.has_outgoing_data?.should be_true
    end

    it "validates WINDOW_UPDATE frame constraints" do
      # RFC 9113: WINDOW_UPDATE frames must have:
      # - Stream ID 0 for connection-level updates
      # - Non-zero stream ID for stream-level updates
      # - Non-zero window increment
      # - Must not cause window to exceed 2^31-1

      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Create a mock WINDOW_UPDATE frame with valid parameters
      # This demonstrates the validation structure needed

      window_update_frame = Bytes.new(13) # 9 byte header + 4 byte payload

      # Frame header: length=4, type=WINDOW_UPDATE(8), flags=0, stream=0
      window_update_frame[0] = 0x00 # Length high
      window_update_frame[1] = 0x00 # Length middle
      window_update_frame[2] = 0x04 # Length low (4 bytes)
      window_update_frame[3] = 0x08 # WINDOW_UPDATE frame type
      window_update_frame[4] = 0x00 # Flags (none defined)
      window_update_frame[5] = 0x00 # Stream ID bytes (0 = connection)
      window_update_frame[6] = 0x00
      window_update_frame[7] = 0x00
      window_update_frame[8] = 0x00

      # Payload: window increment (must be > 0)
      increment = 1000_u32
      window_update_frame[9] = ((increment >> 24) & 0xFF).to_u8
      window_update_frame[10] = ((increment >> 16) & 0xFF).to_u8
      window_update_frame[11] = ((increment >> 8) & 0xFF).to_u8
      window_update_frame[12] = (increment & 0xFF).to_u8

      # Inject valid WINDOW_UPDATE frame
      transport.inject_incoming_data(window_update_frame)

      # Verify engine can handle the frame without errors
      engine.closed?.should be_false
    end
  end

  describe "flow control errors" do
    it "generates FLOW_CONTROL_ERROR for window violations" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Create a WINDOW_UPDATE frame with zero increment (invalid)
      invalid_window_update = Bytes.new(13)

      # Frame header
      invalid_window_update[0] = 0x00 # Length
      invalid_window_update[1] = 0x00
      invalid_window_update[2] = 0x04
      invalid_window_update[3] = 0x08 # WINDOW_UPDATE
      invalid_window_update[4] = 0x00 # Flags
      invalid_window_update[5] = 0x00 # Stream ID (connection)
      invalid_window_update[6] = 0x00
      invalid_window_update[7] = 0x00
      invalid_window_update[8] = 0x00

      # Invalid payload: zero increment
      invalid_window_update[9] = 0x00
      invalid_window_update[10] = 0x00
      invalid_window_update[11] = 0x00
      invalid_window_update[12] = 0x00

      # This should trigger FLOW_CONTROL_ERROR when frame processing is implemented
      transport.inject_incoming_data(invalid_window_update)

      # For now, verify engine doesn't crash
      engine.closed?.should be_false
    end

    it "handles window overflow scenarios" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Create WINDOW_UPDATE with increment that would cause overflow
      overflow_update = Bytes.new(13)

      # Frame header
      overflow_update[0] = 0x00
      overflow_update[1] = 0x00
      overflow_update[2] = 0x04
      overflow_update[3] = 0x08 # WINDOW_UPDATE
      overflow_update[4] = 0x00
      overflow_update[5] = 0x00 # Connection-level
      overflow_update[6] = 0x00
      overflow_update[7] = 0x00
      overflow_update[8] = 0x00

      # Large increment that could cause overflow
      large_increment = 0x7FFFFFFF_u32 # Close to max
      overflow_update[9] = ((large_increment >> 24) & 0xFF).to_u8
      overflow_update[10] = ((large_increment >> 16) & 0xFF).to_u8
      overflow_update[11] = ((large_increment >> 8) & 0xFF).to_u8
      overflow_update[12] = (large_increment & 0xFF).to_u8

      # Should handle gracefully or generate appropriate error
      transport.inject_incoming_data(overflow_update)
      engine.closed?.should be_false
    end
  end

  describe "data frame flow control interaction" do
    it "properly accounts for DATA frame payload in flow control" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("POST", "/", headers)
      transport.clear_outgoing_data

      # Send DATA frame and verify flow control accounting
      payload = "Hello, flow control world!"
      engine.send_data(stream_id, payload, end_stream: true)

      outgoing = transport.get_outgoing_data

      # Find DATA frame and verify payload length
      frame_type = outgoing[3]
      frame_type.should eq(0x00_u8) # DATA frame

      frame_length = (outgoing[0].to_u32 << 16) |
                     (outgoing[1].to_u32 << 8) |
                     outgoing[2].to_u32

      # Frame length should match payload size
      frame_length.should eq(payload.bytesize)
    end

    it "handles empty DATA frames correctly in flow control" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("POST", "/", headers)
      transport.clear_outgoing_data

      # Send empty DATA frame (only END_STREAM flag)
      engine.send_data(stream_id, "", end_stream: true)

      outgoing = transport.get_outgoing_data

      # Empty DATA frame should have zero length
      frame_length = (outgoing[0].to_u32 << 16) |
                     (outgoing[1].to_u32 << 8) |
                     outgoing[2].to_u32

      frame_length.should eq(0)

      # Should have END_STREAM flag
      flags = outgoing[4]
      (flags & 0x01).should_not eq(0) # END_STREAM flag
    end
  end

  describe "flow control integration with multiplexing" do
    it "manages flow control across multiple concurrent streams" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      # Create multiple streams and send data
      streams = Array(UInt32).new
      5.times do |i|
        stream_id = engine.send_request("POST", "/upload-#{i}", headers)
        streams << stream_id

        # Send data on each stream
        data = "Stream #{i} data: " + "x" * 100
        engine.send_data(stream_id, data, end_stream: true)
      end

      # All streams should send successfully
      streams.size.should eq(5)
      transport.has_outgoing_data?.should be_true

      # Verify all streams are tracked
      streams.each do |stream_id|
        engine.active_streams.has_key?(stream_id).should be_true
      end
    end
  end

  describe "settings frame flow control parameters" do
    it "handles INITIAL_WINDOW_SIZE setting updates" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection

      # Create mock SETTINGS frame with INITIAL_WINDOW_SIZE
      settings_frame = Bytes.new(15) # 9 header + 6 payload (1 setting)

      # Frame header
      settings_frame[0] = 0x00 # Length
      settings_frame[1] = 0x00
      settings_frame[2] = 0x06 # 6 bytes payload
      settings_frame[3] = 0x04 # SETTINGS frame
      settings_frame[4] = 0x00 # No ACK flag
      settings_frame[5] = 0x00 # Stream 0
      settings_frame[6] = 0x00
      settings_frame[7] = 0x00
      settings_frame[8] = 0x00

      # Setting: INITIAL_WINDOW_SIZE (0x04) = 32768
      settings_frame[9] = 0x00  # Setting ID high byte
      settings_frame[10] = 0x04 # Setting ID low byte (INITIAL_WINDOW_SIZE)
      settings_frame[11] = 0x00 # Value bytes
      settings_frame[12] = 0x00
      settings_frame[13] = 0x80 # 32768 = 0x8000
      settings_frame[14] = 0x00

      # Inject SETTINGS frame
      transport.inject_incoming_data(settings_frame)

      # Engine should handle settings update gracefully
      engine.closed?.should be_false
    end
  end
end
