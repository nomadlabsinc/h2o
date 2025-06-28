require "./spec_helper"
require "process"

describe "H2 Test Harness Diagnostic" do
  it "tests direct connection to h2-client-test-harness" do
    puts "🧪 Testing direct connection to h2-client-test-harness"
    
    # Start the h2-client-test-harness in background
    puts "Starting h2-client-test-harness container..."
    
    harness_process = Process.new(
      command: "docker",
      args: ["run", "--rm", "-d", "-p", "8080:8080", "h2-test-harness", "3.5/1"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    
    container_id = harness_process.output.gets_to_end.strip
    harness_process.wait
    
    puts "Container ID: #{container_id}"
    
    # Wait for container to start
    sleep 2.seconds
    
    begin
      # Test with very aggressive timeouts
      puts "Creating H2O client with 500ms timeouts..."
      
      client = H2O::H2::Client.new("localhost", 8080,
                                   connect_timeout: 500.milliseconds,
                                   request_timeout: 500.milliseconds,
                                   verify_ssl: false,
                                   use_tls: false)
      
      puts "Making request..."
      
      # This should fail quickly due to invalid preface test
      headers = H2O::Headers{"host" => "localhost:8080"}
      
      start_time = Time.utc
      response = client.request("GET", "/", headers)
      end_time = Time.utc
      
      duration = end_time - start_time
      puts "Request completed in #{duration.total_milliseconds}ms"
      puts "Response status: #{response.status}"
      
      # For test 3.5/1 (invalid preface), we expect a connection error
      if response.status == 0
        puts "✓ Got error response as expected for invalid preface test"
      else
        puts "✗ Unexpected successful response: #{response.status}"
      end
      
    rescue ex : H2O::ConnectionError
      puts "✓ Connection error as expected: #{ex.message}"
    rescue ex : Exception
      puts "✗ Unexpected error: #{ex.class} - #{ex.message}"
      ex.backtrace.first(5).each { |line| puts "  #{line}" }
    ensure
      begin
        client.try(&.close)
      rescue
        # Ignore close errors
      end
      
      # Stop the container
      puts "Stopping container..."
      Process.run("docker", ["stop", container_id], output: Process::Redirect::Close, error: Process::Redirect::Close)
    end
  end

  it "tests with minimal frame validation" do
    puts "🧪 Testing basic frame creation without full validation"
    
    # Test that we can create frames without hanging
    begin
      # Create a simple PING frame manually
      frame_data = Bytes[
        0x00, 0x00, 0x08,        # Length: 8
        0x06,                    # Type: PING
        0x00,                    # Flags: none
        0x00, 0x00, 0x00, 0x00,  # Stream ID: 0
        0x01, 0x02, 0x03, 0x04,  # Ping data
        0x05, 0x06, 0x07, 0x08
      ]
      
      io = IO::Memory.new(frame_data)
      
      start_time = Time.utc
      frame = H2O::Frame.from_io(io, 16384_u32)
      end_time = Time.utc
      
      duration = end_time - start_time
      puts "Frame parsing took #{duration.total_milliseconds}ms"
      
      frame.should be_a(H2O::PingFrame)
      puts "✓ Frame validation completes quickly"
      
      # Ensure timing is reasonable (< 10ms)
      duration.total_milliseconds.should be < 10
      
    rescue ex
      puts "✗ Frame validation failed: #{ex.message}"
      raise ex
    end
  end

  it "tests timeout behavior with deliberate delay" do
    puts "🧪 Testing timeout behavior"
    
    # Create a server that deliberately delays
    server = TCPServer.new("localhost", 0)
    port = server.local_address.port
    
    # Start delayed server
    spawn do
      begin
        socket = server.accept
        # Delay for longer than our timeout
        sleep 1.second
        socket.write("HTTP/1.1 200 OK\r\n\r\n".to_slice)
        socket.close
      rescue
        # Ignore server errors
      end
    end
    
    begin
      start_time = Time.utc
      
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 200.milliseconds,
                                   request_timeout: 200.milliseconds,
                                   verify_ssl: false,
                                   use_tls: false)
      
      headers = H2O::Headers{"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      
      end_time = Time.utc
      duration = end_time - start_time
      
      puts "Request took #{duration.total_milliseconds}ms"
      
      # Should complete within reasonable time (timeout + overhead)
      duration.total_milliseconds.should be < 1000 # Max 1 second
      
      puts "✓ Timeout behavior works correctly"
      
    rescue ex
      end_time = Time.utc
      duration = end_time - start_time
      puts "Request failed after #{duration.total_milliseconds}ms: #{ex.message}"
      
      # Should fail quickly due to timeout
      duration.total_milliseconds.should be < 1000
      
    ensure
      server.try(&.close)
      client.try(&.close)
    end
  end
end