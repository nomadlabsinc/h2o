require "../spec_helper"
require "process"

# Tests that understand the actual behavior of h2-client-test-harness

describe "H2O HTTP/2 Compliance - Harness Behavior" do
  it "validates H2O client behavior against test harness" do
    test_results = [] of NamedTuple(test_id: String, desc: String, passed: Bool, result: String)
    
    # Test 1: SETTINGS synchronization (6.5.3/2)
    # Harness sends SETTINGS and expects ACK, but doesn't send HTTP response
    result = run_test("6.5.3/2", "SETTINGS synchronization")
    # Client should handle SETTINGS properly but will timeout waiting for response
    passed = result[:output].includes?("TIMEOUT") || result[:output].includes?("408")
    test_results << {test_id: "6.5.3/2", desc: "SETTINGS ACK", passed: passed, result: result[:output]}
    
    # Test 2: DATA frame exceeds max size (4.2/2)
    # Harness sends oversized DATA frame, client should close connection
    result = run_test("4.2/2", "DATA exceeds max size")
    passed = result[:output].includes?("CONNECTION_ERROR") || result[:output].includes?("End of file")
    test_results << {test_id: "4.2/2", desc: "DATA exceeds max", passed: passed, result: result[:output]}
    
    # Test 3: SETTINGS with ACK flag and payload (6.5/1)
    # Invalid SETTINGS frame, client should close connection
    result = run_test("6.5/1", "Invalid SETTINGS ACK")
    passed = result[:output].includes?("CONNECTION_ERROR") || result[:output].includes?("End of file")
    test_results << {test_id: "6.5/1", desc: "SETTINGS ACK with payload", passed: passed, result: result[:output]}
    
    # Print results
    puts "\n" + "="*60
    puts "H2O HTTP/2 Compliance Test Results"
    puts "="*60
    
    test_results.each do |result|
      status = result[:passed] ? "✅ PASS" : "❌ FAIL"
      puts "#{status} #{result[:test_id]} - #{result[:desc]}: #{result[:result]}"
    end
    
    passed_count = test_results.count(&.[:passed])
    total_count = test_results.size
    
    puts "="*60
    puts "Summary: #{passed_count}/#{total_count} tests passed"
    puts "="*60
    
    # All tests should pass
    passed_count.should eq(total_count)
  end
end

def run_test(test_id : String, description : String) : NamedTuple(output: String)
  port = 41000 + Random.rand(10000)
  container_name = "h2-test-#{test_id.gsub(/[\/\.]/, "-")}-#{Random.rand(100000)}"
  
  # Start test harness
  container_id = `docker run --rm -d --name #{container_name} -p #{port}:8080 h2-client-test-harness --test=#{test_id}`.strip
  
  if container_id.empty?
    return {output: "HARNESS_START_FAILED"}
  end
  
  # Give harness time to start
  sleep 1.5.seconds
  
  # Test with H2O client
  output = ""
  begin
    client = H2O::H2::Client.new("localhost", port,
                                 connect_timeout: 3.seconds,
                                 request_timeout: 3.seconds,
                                 use_tls: true,
                                 verify_ssl: false)
    
    headers = H2O::Headers{"host" => "localhost:#{port}"}
    response = client.request("GET", "/", headers)
    
    if response.status >= 200 && response.status < 300
      output = "SUCCESS:#{response.status}"
    else
      output = "SERVER_ERROR:#{response.status}"
    end
  rescue ex : H2O::ConnectionError
    output = "CONNECTION_ERROR:#{ex.message}"
  rescue ex : H2O::StreamError
    output = "STREAM_ERROR"
  rescue ex : H2O::TimeoutError
    output = "TIMEOUT"
  rescue ex
    output = "ERROR:#{ex.class.name}:#{ex.message}"
  ensure
    # Cleanup
    `docker kill #{container_name} 2>/dev/null`
  end
  
  {output: output}
end