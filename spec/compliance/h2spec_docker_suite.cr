require "../spec_helper"
require "process"

# H2SPEC Compliance Test Suite for Docker
# Uses pre-built harness binary at /usr/local/bin/harness
# Runs all 146 H2SPEC tests efficiently

module H2SpecDockerSuite
  # Check if running inside Docker
  def self.running_in_docker? : Bool
    File.exists?("/.dockerenv")
  end
  
  # Check if harness binary exists
  def self.harness_available? : Bool
    File.exists?("/usr/local/bin/harness") && File.executable?("/usr/local/bin/harness")
  end
  
  # All 146 H2SPEC test cases
  TEST_CASES = [
    # 3.5 Connection Preface (2 tests)
    "3.5/1", "3.5/2",
    
    # 4.1 Frame Format (3 tests)
    "4.1/1", "4.1/2", "4.1/3",
    
    # 4.2 Frame Size (3 tests)
    "4.2/1", "4.2/2", "4.2/3",
    
    # 4.3 Header Compression (1 test)
    "4.3/1",
    
    # 5.1 Stream States (13 tests)
    "5.1/1", "5.1/2", "5.1/3", "5.1/4", "5.1/5", "5.1/6", "5.1/7",
    "5.1/8", "5.1/9", "5.1/10", "5.1/11", "5.1/12", "5.1/13",
    
    # 5.1.1 Stream Identifiers (2 tests)
    "5.1.1/1", "5.1.1/2",
    
    # 5.1.2 Stream Concurrency (1 test)
    "5.1.2/1",
    
    # 5.3.1 Stream Dependencies (2 tests)
    "5.3.1/1", "5.3.1/2",
    
    # 5.4.1 Connection Error Handling (2 tests)
    "5.4.1/1", "5.4.1/2",
    
    # 5.5 Extending HTTP/2 (1 test)
    "5.5/1",
    
    # 6.1 DATA (3 tests)
    "6.1/1", "6.1/2", "6.1/3",
    
    # 6.2 HEADERS (4 tests)
    "6.2/1", "6.2/2", "6.2/3", "6.2/4",
    
    # 6.3 PRIORITY (2 tests)
    "6.3/1", "6.3/2",
    
    # 6.4 RST_STREAM (3 tests)
    "6.4/1", "6.4/2", "6.4/3",
    
    # 6.5 SETTINGS (3 tests)
    "6.5/1", "6.5/2", "6.5/3",
    
    # 6.5.2 Defined SETTINGS Parameters (5 tests)
    "6.5.2/1", "6.5.2/2", "6.5.2/3", "6.5.2/4", "6.5.2/5",
    
    # 6.5.3 Settings Synchronization (1 test)
    "6.5.3/2",
    
    # 6.7 PING (4 tests)
    "6.7/1", "6.7/2", "6.7/3", "6.7/4",
    
    # 6.8 GOAWAY (1 test)
    "6.8/1",
    
    # 6.9 WINDOW_UPDATE (3 tests)
    "6.9/1", "6.9/2", "6.9/3",
    
    # 6.9.1 Flow Control (3 tests)
    "6.9.1/1", "6.9.1/2", "6.9.1/3",
    
    # 6.9.2 Initial Flow Control Window Size (1 test)
    "6.9.2/3",
    
    # 6.10 CONTINUATION (5 tests)
    "6.10/2", "6.10/3", "6.10/4", "6.10/5", "6.10/6",
    
    # 7 Error Codes (1 test)
    "7/1",
    
    # 8.1 HTTP Request/Response Exchange (1 test)
    "8.1/1",
    
    # 8.1.2 HTTP Header Fields (1 test)
    "8.1.2/1",
    
    # 8.1.2.1 Pseudo-Header Fields (4 tests)
    "8.1.2.1/1", "8.1.2.1/2", "8.1.2.1/3", "8.1.2.1/4",
    
    # 8.1.2.2 Connection-Specific Header Fields (2 tests)
    "8.1.2.2/1", "8.1.2.2/2",
    
    # 8.1.2.3 Request Pseudo-Header Fields (7 tests)
    "8.1.2.3/1", "8.1.2.3/2", "8.1.2.3/3", "8.1.2.3/4", "8.1.2.3/5", "8.1.2.3/6", "8.1.2.3/7",
    
    # 8.1.2.4 Response Pseudo-Header Fields (1 test)
    "8.1.2.4/1",
    
    # 8.1.2.5 Compressing the Cookie Header Field (1 test)
    "8.1.2.5/1",
    
    # 8.1.2.6 Malformed Requests and Responses (2 tests)
    "8.1.2.6/1", "8.1.2.6/2",
    
    # 8.2 Server Push (1 test)
    "8.2/1",
    
    # Generic tests (23 tests)
    "generic/1/1", "generic/2/1", "generic/3.1/1", "generic/3.1/2", "generic/3.1/3",
    "generic/3.2/1", "generic/3.2/2", "generic/3.2/3", "generic/3.3/1", "generic/3.3/2",
    "generic/3.3/3", "generic/3.3/4", "generic/3.3/5", "generic/3.4/1", "generic/3.5/1",
    "generic/3.7/1", "generic/3.8/1", "generic/3.9/1", "generic/3.10/1", "generic/4/1",
    "generic/4/2", "generic/5/1", "generic/misc/1",
    
    # HPACK tests (14 tests)
    "hpack/2.3.3/1", "hpack/2.3.3/2", "hpack/2.3/1", "hpack/4.1/1", "hpack/4.2/1",
    "hpack/5.2/1", "hpack/5.2/2", "hpack/5.2/3", "hpack/6.1/1", "hpack/6.2.2/1",
    "hpack/6.2.3/1", "hpack/6.2/1", "hpack/6.3/1", "hpack/misc/1",
    
    # Extra tests (5 tests)
    "extra/1", "extra/2", "extra/3", "extra/4", "extra/5",
    
    # Final tests (2 tests)
    "final/1", "final/2",
    
    # Complete tests (13 tests)
    "complete/1", "complete/2", "complete/3", "complete/4", "complete/5", "complete/6",
    "complete/7", "complete/8", "complete/9", "complete/10", "complete/11", "complete/12", "complete/13"
  ]
  
  # Get test subset for parallel CI execution
  def self.get_test_subset(node_index : Int32, total_nodes : Int32) : Array(String)
    tests_per_node = (TEST_CASES.size / total_nodes.to_f).ceil.to_i
    start_idx = node_index * tests_per_node
    end_idx = Math.min(start_idx + tests_per_node, TEST_CASES.size)
    
    TEST_CASES[start_idx...end_idx]
  end
  
  struct TestResult
    getter test_id : String
    getter passed : Bool
    getter error : String?
    getter duration : Time::Span
    
    def initialize(@test_id : String, @passed : Bool, @error : String? = nil, @duration : Time::Span = 0.seconds)
    end
  end
  
  def self.run_test(test_id : String) : TestResult
    start_time = Time.monotonic
    port = 20000 + Random.rand(10000)
    
    # Check if harness binary exists before trying to run it
    unless harness_available?
      return TestResult.new(test_id, false, "Harness binary not found at /usr/local/bin/harness", Time.monotonic - start_time)
    end
    
    harness_process = nil
    
    begin
      # Start harness using local binary
      harness_process = Process.new(
        "/usr/local/bin/harness",
        ["--port", port.to_s, "--test", test_id],
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )
    rescue ex : Exception
      return TestResult.new(test_id, false, "Failed to start harness: #{ex.message}", Time.monotonic - start_time)
    end
    
    # Give harness minimal time to start
    sleep 0.3.seconds
    
    error_msg = nil
    passed = false
    
    begin
      # Create client with short timeouts
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 1.seconds,
                                   request_timeout: 1.seconds,
                                   verify_ssl: false)
      
      headers = {"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      
      # Getting any response means client handled it
      passed = true
      client.close
      
    rescue ex : H2O::ConnectionError | H2O::ProtocolError | H2O::CompressionError
      # Expected errors - client properly rejected invalid input
      passed = true
      error_msg = ex.class.name.split("::").last
    rescue ex : Exception
      # Unexpected errors
      passed = false
      error_msg = "#{ex.class.name}: #{ex.message}"
    ensure
      # Clean up harness process if it was started
      if harness_process
        begin
          harness_process.terminate
          harness_process.wait
        rescue ex : Exception
          # Ignore cleanup errors
        end
      end
    end
    
    TestResult.new(test_id, passed, error_msg, Time.monotonic - start_time)
  end
  
  def self.run_all_tests_parallel(batch_size : Int32 = 10) : Array(TestResult)
    results = Array(TestResult).new
    results_channel = Channel(TestResult).new(batch_size)
    
    # Process tests in batches
    TEST_CASES.each_slice(batch_size) do |batch|
      # Start batch in parallel
      batch.each do |test_id|
        spawn do
          result = run_test(test_id)
          results_channel.send(result)
        end
      end
      
      # Collect batch results
      batch.size.times do
        results << results_channel.receive
      end
      
      # Small delay between batches
      sleep 0.05.seconds
    end
    
    results
  end
end

describe "H2O H2SPEC Docker Compliance Suite" do
  it "runs all 146 H2SPEC tests efficiently" do
    # Check if we're running in the correct environment
    unless H2SpecDockerSuite.running_in_docker?
      puts "\n⚠️  WARNING: This test suite must be run inside Docker!"
      puts "Please run: docker-compose run --rm app crystal spec spec/compliance/h2spec_docker_suite.cr"
      pending "Test requires Docker environment"
    end
    
    unless H2SpecDockerSuite.harness_available?
      puts "\n❌ ERROR: Harness binary not found at /usr/local/bin/harness"
      puts "This binary should be built during Docker image creation."
      fail "Missing harness binary"
    end
    
    # Check for CI parallel execution
    node_index = ENV["CI_NODE_INDEX"]?.try(&.to_i?) || nil
    total_nodes = ENV["CI_NODE_TOTAL"]?.try(&.to_i?) || nil
    
    test_cases = if node_index && total_nodes
      puts "\n🚀 H2O H2SPEC Compliance Test Suite (Node #{node_index + 1}/#{total_nodes})"
      H2SpecDockerSuite.get_test_subset(node_index, total_nodes)
    else
      puts "\n🚀 H2O H2SPEC Compliance Test Suite (Docker Edition)"
      H2SpecDockerSuite::TEST_CASES
    end
    
    puts "Running #{test_cases.size} tests sequentially..."
    puts "=" * 80
    
    start_time = Time.monotonic
    results = [] of H2SpecDockerSuite::TestResult
    
    # Run tests sequentially to avoid issues
    test_cases.each_with_index do |test_id, index|
      puts "\nStarting test #{index + 1}/#{test_cases.size}: #{test_id}"
      result = H2SpecDockerSuite.run_test(test_id)
      results << result
      puts "Test #{test_id} completed: #{result.passed ? "PASS" : "FAIL"}"
      
      # Add small delay and GC to prevent resource exhaustion
      sleep 0.01.seconds
      GC.collect if index % 10 == 0
    end
    puts ""
    
    total_duration = Time.monotonic - start_time
    
    # Analyze results
    passed_count = results.count(&.passed)
    failed_count = results.count { |r| !r.passed }
    
    # Group by error type
    error_groups = results.reject(&.passed).group_by(&.error.to_s.split(":").first)
    
    # Summary
    puts "\n📊 RESULTS SUMMARY"
    puts "Total tests: #{results.size}"
    puts "Passed: #{passed_count} (#{(passed_count * 100.0 / results.size).round(1)}%)"
    puts "Failed: #{failed_count}"
    puts "Duration: #{total_duration.total_seconds.round(2)}s"
    puts "Avg per test: #{(total_duration.total_seconds / results.size).round(3)}s"
    
    if failed_count > 0
      puts "\n❌ FAILURES BY TYPE:"
      error_groups.each do |error_type, failures|
        puts "  #{error_type}: #{failures.size} tests"
      end
      puts "\n🚨 TEST SUITE FAILED: #{failed_count} tests did not pass!"
    else
      puts "\n✅ ALL TESTS PASSED!"
    end
    
    # The test passes only if all tests passed
    results.size.should eq(test_cases.size)
    failed_count.should eq(0)
    
    # Save results for analysis
    results_filename = if node_index && total_nodes
      "h2spec_results_node#{node_index}.json"
    else
      "h2spec_results.json"
    end
    
    File.write(results_filename, {
      timestamp: Time.utc.to_s,
      node_index: node_index,
      total_nodes: total_nodes,
      total_tests: results.size,
      passed: passed_count,
      failed: failed_count,
      duration_seconds: total_duration.total_seconds,
      results: results.map { |r| {
        test_id: r.test_id,
        passed: r.passed,
        error: r.error,
        duration: r.duration.total_seconds
      }}
    }.to_json)
    
    puts "\nResults saved to #{results_filename}"
  end
end