require "../spec_helper"
require "process"

# Detailed test to understand what the harness is actually doing

describe "H2O HTTP/2 Detailed Compliance" do
  it "examines specific test case behavior" do
    # Test case 4.2/2: DATA frame exceeds max size
    port = 42000
    container_name = "h2-detailed-test"
    test_id = "4.2/2"
    
    # Kill any existing container
    `docker kill #{container_name} 2>/dev/null`
    
    puts "\n🔍 Testing case #{test_id}: DATA frame exceeds max size"
    
    # Start test harness
    container_id = `docker run --rm -d --name #{container_name} -p #{port}:8080 h2-client-test-harness --test=#{test_id}`.strip
    puts "Started container: #{container_id[0..12]}..."
    
    sleep 1.5.seconds
    
    # Get initial logs
    puts "\nHarness logs before connection:"
    puts `docker logs #{container_name} 2>&1`
    
    # Test with H2O client with debug logging
    puts "\nConnecting H2O client..."
    begin
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 5.seconds,
                                   request_timeout: 5.seconds,
                                   use_tls: true,
                                   verify_ssl: false)
      
      headers = H2O::Headers{"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      
      puts "Response received: Status #{response.status}"
      puts "Headers: #{response.headers}"
      puts "Body: #{response.body[0..100] if response.body}" if response.body && !response.body.empty?
    rescue ex
      puts "Exception: #{ex.class.name} - #{ex.message}"
    end
    
    # Get final logs
    puts "\nHarness logs after test:"
    puts `docker logs #{container_name} 2>&1 | tail -20`
    
    # Cleanup
    `docker kill #{container_name} 2>/dev/null`
    
    # Now test a simpler case
    puts "\n" + "="*60
    puts "Testing case 6.5/1: SETTINGS with ACK flag and payload"
    
    container_name = "h2-detailed-test2"
    test_id = "6.5/1"
    
    # Start test harness
    container_id = `docker run --rm -d --name #{container_name} -p #{port}:8080 h2-client-test-harness --test=#{test_id}`.strip
    puts "Started container: #{container_id[0..12]}..."
    
    sleep 1.5.seconds
    
    # Test with H2O client
    puts "\nConnecting H2O client..."
    begin
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 3.seconds,
                                   request_timeout: 3.seconds,
                                   use_tls: true,
                                   verify_ssl: false)
      
      headers = H2O::Headers{"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      
      puts "Response received: Status #{response.status}"
    rescue ex
      puts "Exception: #{ex.class.name} - #{ex.message}"
      if ex.is_a?(H2O::ConnectionError)
        puts "This is the expected behavior - connection should fail on invalid SETTINGS"
      end
    end
    
    # Get logs
    puts "\nHarness logs:"
    puts `docker logs #{container_name} 2>&1`
    
    # Cleanup
    `docker kill #{container_name} 2>/dev/null`
    
    true.should be_true
  end
end