require "../spec_helper"
require "process"

# Simple compliance test that runs key test cases directly

describe "H2O HTTP/2 Basic Compliance" do
  it "validates critical HTTP/2 behaviors" do
    # Test case 1: Normal SETTINGS ACK (should succeed)
    test_result = run_harness_test("6.5.3/2", "SETTINGS ACK", expect_success: true)
    test_result[:passed].should be_true
    
    # Test case 2: DATA frame exceeds max size (should fail with connection error)
    test_result = run_harness_test("4.2/2", "DATA exceeds max", expect_success: false)
    test_result[:passed].should be_true
    
    # Test case 3: SETTINGS with ACK flag and payload (should fail)
    test_result = run_harness_test("6.5/1", "SETTINGS ACK with payload", expect_success: false)
    test_result[:passed].should be_true
  end
end

def run_harness_test(test_id : String, description : String, expect_success : Bool) : NamedTuple(passed: Bool, output: String)
  port = 40000 + Random.rand(10000)
  container_name = "h2-test-#{test_id.gsub(/[\/\.]/, "-")}-#{Random.rand(100000)}"
  
  # Start test harness
  container_id = `docker run --rm -d --name #{container_name} -p #{port}:8080 h2-client-test-harness --test=#{test_id}`.strip
  
  if container_id.empty?
    return {passed: false, output: "Failed to start harness"}
  end
  
  # Give harness time to start
  sleep 1.5.seconds
  
  # Test with H2O client
  output = ""
  begin
    client = H2O::H2::Client.new("localhost", port,
                                 connect_timeout: 2.seconds,
                                 request_timeout: 2.seconds,
                                 use_tls: true,
                                 verify_ssl: false)
    
    headers = H2O::Headers{"host" => "localhost:#{port}"}
    response = client.request("GET", "/", headers)
    
    if response.status >= 200 && response.status < 300
      output = "SUCCESS"
    else
      output = "SERVER_ERROR:#{response.status}"
    end
  rescue ex : H2O::ConnectionError
    output = "CONNECTION_ERROR"
  rescue ex : H2O::StreamError
    output = "STREAM_ERROR"
  rescue ex : H2O::TimeoutError
    output = "TIMEOUT"
  rescue ex
    output = "ERROR:#{ex.class.name}"
  ensure
    # Cleanup
    `docker kill #{container_name} 2>/dev/null`
  end
  
  # Determine if test passed
  passed = if expect_success
    output == "SUCCESS"
  else
    output != "SUCCESS"
  end
  
  puts "Test #{test_id} (#{description}): #{passed ? "✅ PASS" : "❌ FAIL"} - #{output}"
  
  {passed: passed, output: output}
end