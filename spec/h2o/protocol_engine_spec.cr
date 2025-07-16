require "../spec_helper"
require "../support/protocol_engine_test_helper"
require "../support/in_memory_transport"

describe "H2O::ProtocolEngine" do
  describe "basic functionality" do
    it "should initialize with transport adapter" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      engine.io_adapter.should eq(transport)
      engine.closed?.should be_false
      engine.connection_established.should be_false
    end

    it "should establish HTTP/2 connection" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Establish connection with proper handshake simulation
      result = H2O::Test::ProtocolEngineTestHelper.establish_test_connection(engine, transport)
      result.should be_true
      
      # Verify preface was sent
      outgoing = transport.get_outgoing_data
      outgoing.size.should be > 0

      # Should start with HTTP/2 connection preface
      preface_string = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
      String.new(outgoing[0, preface_string.size]).should eq(preface_string)
      
      # Connection should be established
      engine.connection_established.should be_true
    end

    it "should handle connection closure" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      closed_callback_called = false
      engine.on_connection_closed = -> {
        closed_callback_called = true
        nil
      }

      engine.close
      engine.closed?.should be_true
      transport.closed?.should be_true
      closed_callback_called.should be_true
    end

    it "should send HTTP/2 requests" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      # Establish connection with proper handshake
      H2O::Test::ProtocolEngineTestHelper.establish_test_connection(engine, transport)
      transport.clear_outgoing_data # Clear preface data

      # Send a request
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      headers["user-agent"] = "H2O-Client/1.0"

      stream_id = engine.send_request("GET", "/", headers)
      stream_id.should eq(1_u32) # First client stream ID

      # Verify data was written
      transport.has_outgoing_data?.should be_true
      outgoing = transport.get_outgoing_data
      outgoing.size.should be > 0
    end

    it "should handle errors gracefully" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)

      error_received = nil
      engine.on_error = ->(ex : Exception) {
        error_received = ex
        nil
      }

      # Try to send request without establishing connection
      headers = H2O::Headers.new
      headers["host"] = "example.com"

      expect_raises(H2O::ConnectionError, /Connection not established/) do
        engine.send_request("GET", "/", headers)
      end
    end

    it "should validate RFC 9113 header compliance" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      H2O::Test::ProtocolEngineTestHelper.establish_test_connection(engine, transport)

      # Test with invalid header (uppercase)
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      headers["Test-Header"] = "value" # Uppercase - should fail

      expect_raises(H2O::CompressionError, /Invalid character in field name/) do
        engine.send_request("GET", "/", headers)
      end
    end

    it "should allocate stream IDs correctly" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      H2O::Test::ProtocolEngineTestHelper.establish_test_connection(engine, transport)

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      # Client should use odd stream IDs starting from 1
      stream_id1 = engine.send_request("GET", "/path1", headers)
      stream_id2 = engine.send_request("GET", "/path2", headers)
      stream_id3 = engine.send_request("GET", "/path3", headers)

      stream_id1.should eq(1_u32)
      stream_id2.should eq(3_u32)
      stream_id3.should eq(5_u32)
    end
  end

  describe "frame handling" do
    it "should send data frames" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      H2O::Test::ProtocolEngineTestHelper.establish_test_connection(engine, transport)

      headers = H2O::Headers.new
      headers["host"] = "example.com"

      stream_id = engine.send_request("POST", "/", headers)
      transport.clear_outgoing_data

      # Send data
      engine.send_data(stream_id, "Hello, world!", end_stream: true)

      transport.has_outgoing_data?.should be_true
    end

    it "should handle ping frames" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      transport.clear_outgoing_data

      # Send ping
      rtt = engine.ping
      rtt.should_not be_nil

      transport.has_outgoing_data?.should be_true
    end
  end
end
