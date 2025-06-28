require "../spec_helper"
require "process"
require "json"
require "colorize"

# Optimized HTTP/2 Protocol Compliance Test Suite
# Runs multiple tests against a single harness instance for efficiency

module H2ComplianceOptimized
  # Expected behavior for each test case
  enum ExpectedBehavior
    Success          # Client should complete request successfully
    ConnectionError  # Client should detect connection-level error and close
    StreamError      # Client should send RST_STREAM with appropriate error code
    Timeout          # Client connection should timeout (server sends nothing)
    GoAway           # Client should handle GOAWAY gracefully
  end

  # Test case definition
  struct TestCase
    getter id : String
    getter description : String
    getter expected : ExpectedBehavior
    getter error_code : H2O::ErrorCode?
    
    def initialize(@id : String, @description : String, @expected : ExpectedBehavior, @error_code : H2O::ErrorCode? = nil)
    end
  end

  # Test result tracking
  struct TestResult
    getter test_case : TestCase
    getter passed : Bool
    getter actual_behavior : String
    getter error_details : String?
    getter duration : Time::Span
    
    def initialize(@test_case : TestCase, @passed : Bool, @actual_behavior : String, 
                   @error_details : String? = nil, @duration : Time::Span = 0.seconds)
    end
  end

  # Subset of critical tests for quick validation
  QUICK_TEST_CASES = [
    # Test that should succeed
    TestCase.new("6.5.3/2", "SETTINGS ACK expected", ExpectedBehavior::Success),
    
    # Connection errors
    TestCase.new("4.2/2", "DATA frame exceeds max size", ExpectedBehavior::ConnectionError, H2O::ErrorCode::FrameSizeError),
    TestCase.new("6.5/1", "SETTINGS with ACK and payload", ExpectedBehavior::ConnectionError, H2O::ErrorCode::FrameSizeError),
    TestCase.new("6.5/2", "SETTINGS with non-zero stream ID", ExpectedBehavior::ConnectionError, H2O::ErrorCode::ProtocolError),
    
    # Stream errors
    TestCase.new("5.1/5", "DATA to half-closed stream", ExpectedBehavior::StreamError, H2O::ErrorCode::StreamClosed),
  ]

  class ComplianceRunner
    def self.run_quick_tests : Array(TestResult)
      results = [] of TestResult
      
      # Start a single harness instance that can run multiple tests
      container_name = "h2-compliance-test-#{Random.rand(100000)}"
      port = 30000 + Random.rand(20000)
      
      puts "\n🚀 Starting H2 compliance test harness on port #{port}..."
      
      # Build command to run harness in multi-test mode
      docker_cmd = [
        "docker", "run", "--rm", "-d",
        "--name", container_name,
        "-p", "#{port}:8080",
        "h2-client-test-harness",
        "--harness-only"
      ]
      
      docker_result = Process.run(docker_cmd[0], docker_cmd[1..], output: :pipe, error: :pipe)
      unless docker_result.success?
        puts "❌ Failed to start test harness: #{docker_result.error}"
        return results
      end
      
      # Give harness time to start
      sleep 1.seconds
      
      begin
        QUICK_TEST_CASES.each_with_index do |test_case, index|
          print "[#{index + 1}/#{QUICK_TEST_CASES.size}] Testing #{test_case.id}: #{test_case.description.ljust(40)} "
          
          result = run_single_test(test_case, port)
          results << result
          
          if result.passed
            puts "✅ PASS".colorize(:green)
          else
            puts "❌ FAIL (expected #{test_case.expected}, got #{result.actual_behavior})".colorize(:red)
          end
        end
      ensure
        # Clean up container
        puts "\n🧹 Cleaning up test harness..."
        Process.run("docker", ["kill", container_name], output: :pipe, error: :pipe)
      end
      
      results
    end
    
    private def self.run_single_test(test_case : TestCase, harness_port : Int32) : TestResult
      start_time = Time.monotonic
      
      begin
        # Configure the harness to run specific test by making a control request
        # The harness should expose an endpoint to switch test modes
        actual_behavior = test_client_behavior(harness_port, test_case.id)
        
        # Determine if test passed
        passed = case test_case.expected
        when .success?
          actual_behavior == "Success"
        when .connection_error?
          actual_behavior.starts_with?("ConnectionError") || 
          actual_behavior.starts_with?("ProtocolError") ||
          actual_behavior == "ConnectionClosed"
        when .stream_error?
          actual_behavior.starts_with?("StreamError") ||
          actual_behavior.starts_with?("StreamReset")
        when .timeout?
          actual_behavior == "Timeout" || actual_behavior == "ConnectionTimeout"
        when .go_away?
          actual_behavior.starts_with?("GoAway") || 
          actual_behavior.starts_with?("ConnectionClosed")
        else
          false
        end
        
        TestResult.new(test_case, passed, actual_behavior, nil, Time.monotonic - start_time)
        
      rescue ex
        TestResult.new(test_case, false, "TestError", ex.message, Time.monotonic - start_time)
      end
    end
    
    private def self.test_client_behavior(port : Int32, test_id : String) : String
      begin
        # Create H2O client with appropriate timeouts
        client = H2O::H2::Client.new("localhost", port,
                                     connect_timeout: 3.seconds,
                                     request_timeout: 3.seconds,
                                     verify_ssl: false)
        
        # Make request with test ID in header to trigger specific test behavior
        headers = H2O::Headers{
          "host" => "localhost:#{port}",
          "x-test-case" => test_id
        }
        
        response = client.request("GET", "/", headers)
        
        # Check response
        if response.status >= 200 && response.status < 300
          "Success"
        else
          "ServerError:#{response.status}"
        end
        
      rescue ex : H2O::ConnectionError
        case ex
        when H2O::ConnectionTimeoutError
          "ConnectionTimeout"
        when H2O::ProtocolError
          "ProtocolError:#{ex.message}"
        when H2O::ConnectionClosedError
          "ConnectionClosed"
        else
          "ConnectionError:#{ex.message}"
        end
      rescue ex : H2O::StreamError
        "StreamError:#{ex.error_code}"
      rescue ex : H2O::TimeoutError
        "Timeout"
      rescue ex
        "Error:#{ex.class.name}:#{ex.message}"
      end
    end
  end
end

# Run the optimized compliance test
describe "H2O Optimized Compliance Test" do
  it "validates key HTTP/2 compliance behaviors" do
    puts "\n" + "="*80
    puts "H2O HTTP/2 Compliance Test Suite (Optimized)".colorize(:cyan).bold
    puts "="*80
    
    results = H2ComplianceOptimized::ComplianceRunner.run_quick_tests
    
    # Summary
    passed_count = results.count(&.passed)
    total_count = results.size
    
    puts "\n" + "="*80
    puts "Test Summary:".colorize(:cyan).bold
    puts "✅ Passed: #{passed_count}/#{total_count}"
    puts "❌ Failed: #{total_count - passed_count}/#{total_count}"
    
    if passed_count < total_count
      puts "\nFailed Tests:".colorize(:red).bold
      results.select { |r| !r.passed }.each do |result|
        puts "  • #{result.test_case.id}: Expected #{result.test_case.expected}, got #{result.actual_behavior}"
      end
    end
    
    puts "="*80
    
    # All tests should pass for compliance
    passed_count.should eq(total_count)
  end
end