require "./spec_helper"

describe "H2O Client Diagnostic Tests" do
  it "creates client with very short timeouts" do
    # Test basic client creation with strict timeouts
    client = nil
    begin
      client = H2O::H2::Client.new("localhost", 9999,
                                   connect_timeout: 100.milliseconds,
                                   request_timeout: 100.milliseconds,
                                   verify_ssl: false)
      
      # This should fail quickly due to no server
      headers = H2O::Headers{"host" => "localhost:9999"}
      response = client.request("GET", "/", headers)
      
      # Should get error response with status 0
      response.status.should eq(0)
      response.error.should_not be_nil
      puts "✓ Connection failed as expected: #{response.error}"
    rescue ex : IO::Error
      # Expected - connection should fail during TLS setup
      puts "✓ Connection failed as expected during setup: #{ex.message}"
    rescue ex : Exception
      # Unexpected error type
      puts "✗ Unexpected error: #{ex.class} - #{ex.message}"
      raise ex
    ensure
      begin
        client.try(&.close)
      rescue
        # Ignore close errors
      end
    end
  end

  it "tests frame validation directly" do
    # Test that our strict validation works correctly
    begin
      # This should pass validation
      frame_data = Bytes[
        0x00, 0x00, 0x08,  # Length: 8
        0x06,              # Type: PING
        0x00,              # Flags: none
        0x00, 0x00, 0x00, 0x00,  # Stream ID: 0
        0x01, 0x02, 0x03, 0x04,  # Ping data
        0x05, 0x06, 0x07, 0x08
      ]
      
      io = IO::Memory.new(frame_data)
      frame = H2O::Frame.from_io(io, 16384_u32)
      
      frame.should be_a(H2O::PingFrame)
      puts "✓ Frame validation works correctly"
    rescue ex
      puts "✗ Frame validation failed: #{ex.message}"
      raise ex
    end
  end

  it "tests invalid frame rejection" do
    # Test that invalid frames are properly rejected
    begin
      # Invalid PING frame with non-zero stream ID (should fail)
      frame_data = Bytes[
        0x00, 0x00, 0x08,  # Length: 8
        0x06,              # Type: PING
        0x00,              # Flags: none
        0x00, 0x00, 0x00, 0x01,  # Stream ID: 1 (INVALID for PING)
        0x01, 0x02, 0x03, 0x04,  # Ping data
        0x05, 0x06, 0x07, 0x08
      ]
      
      io = IO::Memory.new(frame_data)
      H2O::Frame.from_io(io, 16384_u32)
      
      # Should not reach here
      fail "Invalid frame was accepted"
    rescue ex : H2O::ConnectionError
      # Expected - frame should be rejected
      puts "✓ Invalid frame rejected as expected: #{ex.message}"
    rescue ex
      puts "✗ Wrong exception type: #{ex.class} - #{ex.message}"
      raise ex
    end
  end

  it "tests connection preface validation" do
    # Test connection preface behavior
    begin
      # Create a mock server on a random port
      server = TCPServer.new("localhost", 0)
      port = server.local_address.port
      
      # Start server in background
      server_fiber = spawn do
        begin
          socket = server.accept
          # Send invalid connection preface
          socket.write("INVALID PREFACE\r\n\r\n".to_slice)
          socket.close
        rescue
          # Ignore server errors
        end
      end
      
      # Test client with very short timeout
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 200.milliseconds,
                                   request_timeout: 200.milliseconds,
                                   verify_ssl: false,
                                   use_tls: false) # Use plain TCP for testing
      
      headers = H2O::Headers{"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      
      # Should get error response
      response.status.should eq(0)
      puts "✓ Connection preface validation triggered"
      
    rescue ex : H2O::ConnectionError
      puts "✓ Connection error as expected: #{ex.message}"
    rescue ex : Exception
      puts "✗ Unexpected error: #{ex.class} - #{ex.message}"
      ex.backtrace.each { |line| puts "  #{line}" }
      raise ex
    ensure
      server.try(&.close)
      client.try(&.close)
    end
  end
end