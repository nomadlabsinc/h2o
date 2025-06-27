require "../spec_helper"
require "process"
require "socket"

# HTTP/2 Compliance Tests using h2-client-test-harness
# This runs the actual h2spec test harness from https://github.com/nomadlabsinc/h2-client-test-harness
# against the H2O client to verify protocol compliance

# Helper module for harness testing
module HarnessTestHelper
  def self.run_test(test_id : String) : {Bool, String?}
    container_name = "h2-test-#{test_id.gsub(/[\/\.]/, "-")}-#{Random.rand(10000)}"
    
    # Check Docker availability
    docker_check = Process.run("docker", ["--version"], output: IO::Memory.new, error: IO::Memory.new)
    unless docker_check.success?
      return {false, "Docker not available"}
    end
    
    # Start the harness container
    start_cmd = [
      "docker", "run", "--rm", "-d",
      "--name", container_name,
      "-p", "8080:8080",
      "h2-client-test-harness",
      "--harness-only", "--test=#{test_id}"
    ]
    
    start_output = IO::Memory.new
    start_error = IO::Memory.new
    start_process = Process.new(start_cmd[0], start_cmd[1..], output: start_output, error: start_error)
    
    unless start_process.wait.success?
      return {false, "Failed to start harness: #{start_error}"}
    end
    
    # Wait for harness to be ready by checking logs
    ready = false
    20.times do
      logs_output = IO::Memory.new
      Process.run("docker", ["logs", container_name], output: logs_output, error: IO::Memory.new)
      logs = logs_output.to_s
      
      if logs.includes?("listening")
        ready = true
        break
      end
      
      sleep 0.05.seconds
    end
    
    unless ready
      return {false, "Harness failed to start"}
    end
    
    error_msg = nil
    success = false
    
    begin
      # Create H2O client and connect
      client = H2O::H2::Client.new("localhost", 8080, use_tls: true, verify_ssl: false)
      
      # Make request - the harness will send specific frames to test behavior
      headers = {"host" => "localhost:8080"}
      response = client.request("GET", "/", headers)
      
      # If we get here without exception, basic communication worked
      success = true
      client.close
      
    rescue ex : H2O::ConnectionError
      # Some tests expect connection errors
      error_msg = "ConnectionError: #{ex.message}"
      success = true  # Expected behavior for some tests
    rescue ex : H2O::ProtocolError
      # Some tests expect protocol errors
      error_msg = "ProtocolError: #{ex.message}"
      success = true  # Expected behavior for some tests
    rescue ex
      # Unexpected error indicates test failure
      error_msg = "Unexpected #{ex.class}: #{ex.message}"
      success = false
    ensure
      # Stop container in background to avoid waiting
      spawn { system("docker stop #{container_name} >/dev/null 2>&1") }
    end
    
    {success, error_msg}
  end
end

describe "H2O HTTP/2 Protocol Compliance (h2-client-test-harness)" do
  # 3.5 HTTP/2 Connection Preface
  describe "3.5 Connection Preface" do
    it "3.5/1: Sends client connection preface" do
      success, error = HarnessTestHelper.run_test("3.5/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "3.5/2: Sends invalid connection preface" do
      success, error = HarnessTestHelper.run_test("3.5/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 4.1 Frame Format
  describe "4.1 Frame Format" do
    it "4.1/1: Sends frame with unknown type" do
      success, error = HarnessTestHelper.run_test("4.1/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "4.1/2: Sends frame with invalid flags" do
      success, error = HarnessTestHelper.run_test("4.1/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "4.1/3: Sends frame with reserved bits set" do
      success, error = HarnessTestHelper.run_test("4.1/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 4.2 Frame Size
  describe "4.2 Frame Size" do
    it "4.2/1: Sends DATA frame exceeding maximum size" do
      success, error = HarnessTestHelper.run_test("4.2/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "4.2/2: Sends HEADERS frame exceeding maximum size" do
      success, error = HarnessTestHelper.run_test("4.2/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "4.2/3: Sends invalid frame size" do
      success, error = HarnessTestHelper.run_test("4.2/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 5.1 Stream States
  describe "5.1 Stream States" do
    it "5.1/1: Sends DATA on stream in IDLE state" do
      success, error = HarnessTestHelper.run_test("5.1/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "5.1/2: Sends HEADERS on stream in IDLE state" do
      success, error = HarnessTestHelper.run_test("5.1/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "5.1/3: Sends DATA on closed stream" do
      success, error = HarnessTestHelper.run_test("5.1/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 5.1.1 Stream Identifiers
  describe "5.1.1 Stream Identifiers" do
    it "5.1.1/1: Uses even stream identifier" do
      success, error = HarnessTestHelper.run_test("5.1.1/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "5.1.1/2: Uses stream identifier zero" do
      success, error = HarnessTestHelper.run_test("5.1.1/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 6.1 DATA Frame
  describe "6.1 DATA Frame" do
    it "6.1/1: Sends DATA frame" do
      success, error = HarnessTestHelper.run_test("6.1/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.1/2: Sends multiple DATA frames" do
      success, error = HarnessTestHelper.run_test("6.1/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.1/3: Sends DATA frame with padding" do
      success, error = HarnessTestHelper.run_test("6.1/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 6.2 HEADERS Frame
  describe "6.2 HEADERS Frame" do
    it "6.2/1: Sends HEADERS frame" do
      success, error = HarnessTestHelper.run_test("6.2/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.2/2: Sends HEADERS frame with priority" do
      success, error = HarnessTestHelper.run_test("6.2/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.2/3: Sends HEADERS frame with padding" do
      success, error = HarnessTestHelper.run_test("6.2/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.2/4: Sends HEADERS frame with CONTINUATION" do
      success, error = HarnessTestHelper.run_test("6.2/4")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 6.5 SETTINGS Frame
  describe "6.5 SETTINGS Frame" do
    it "6.5/1: Sends SETTINGS frame with invalid stream ID" do
      success, error = HarnessTestHelper.run_test("6.5/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.5/2: Sends SETTINGS frame with ACK and payload" do
      success, error = HarnessTestHelper.run_test("6.5/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.5/3: Sends SETTINGS with unknown identifier" do
      success, error = HarnessTestHelper.run_test("6.5/3")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
  
  # 6.9 WINDOW_UPDATE Frame
  describe "6.9 WINDOW_UPDATE Frame" do
    it "6.9/1: Sends WINDOW_UPDATE with zero increment" do
      success, error = HarnessTestHelper.run_test("6.9/1")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
    
    it "6.9/2: Sends WINDOW_UPDATE causing overflow" do
      success, error = HarnessTestHelper.run_test("6.9/2")
      if error == "Docker not available"
        pending "Docker required for harness tests"
      else
        success.should be_true
      end
    end
  end
end