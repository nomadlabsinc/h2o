require "../spec_helper"
require "process"

# Demonstration of proper HTTP/2 compliance testing
# Tests a small subset to show how the harness should work

describe "H2O HTTP/2 Compliance Demo" do
  it "demonstrates proper compliance testing" do
    # Test just a few key cases to demonstrate the concept
    test_cases = [
      # This should pass - client should handle SETTINGS and send ACK
      {id: "6.5.3/2", desc: "SETTINGS ACK required", should_pass: true},
      
      # This should fail - client should detect oversized frame
      {id: "4.2/2", desc: "Oversized DATA frame", should_pass: false},
      
      # This should fail - client should detect protocol error
      {id: "6.5/1", desc: "SETTINGS with ACK and payload", should_pass: false},
    ]
    
    puts "\n🧪 HTTP/2 Compliance Test Demo"
    puts "=" * 60
    
    passed = 0
    failed = 0
    
    test_cases.each do |test|
      print "Testing #{test[:id]}: #{test[:desc]}... "
      
      # Use the h2-client-test-harness from the cloned repo
      harness_path = File.expand_path("h2-client-test-harness")
      unless File.exists?(harness_path)
        puts "❌ SKIP (harness not found at #{harness_path})"
        next
      end
      
      container_name = "h2-demo-#{test[:id].gsub(/[\/\.]/, "-")}-#{Random.rand(10000)}"
      port = 50000 + Random.rand(10000)
      
      begin
        # Build the harness image if needed
        build_status = Process.run(
          "docker", 
          ["build", "-t", "h2-client-test-harness", "."],
          chdir: harness_path,
          output: :pipe,
          error: :pipe
        )
        
        unless build_status.success?
          puts "❌ SKIP (failed to build harness)"
          next
        end
        
        # Run the test harness
        docker_cmd = [
          "docker", "run", "--rm", "-d", 
          "--name", container_name,
          "-p", "#{port}:8080",
          "h2-client-test-harness",
          "--test=#{test[:id]}"
        ]
        
        docker_output = IO::Memory.new
        docker_status = Process.run(docker_cmd[0], docker_cmd[1..], output: docker_output, error: :pipe)
        
        unless docker_status.success?
          puts "❌ SKIP (failed to start harness)"
          next
        end
        
        sleep 1.5.seconds # Give harness time to start
        
        # Try to connect with h2o client
        client_succeeded = false
        error_type = nil
        
        begin
          client = H2O::H2::Client.new("localhost", port, 
                                       connect_timeout: 2.seconds,
                                       request_timeout: 2.seconds,
                                       verify_ssl: false)
          
          # Make a simple request
          response = client.request("GET", "/", H2O::Headers{"host" => "localhost"})
          client.close
          
          client_succeeded = true
          
        rescue ex : H2O::ProtocolError
          error_type = "ProtocolError"
        rescue ex : H2O::FrameError
          error_type = "FrameError"
        rescue ex : H2O::ConnectionError
          error_type = "ConnectionError"
        rescue ex : IO::Error
          error_type = "IO::Error"
        rescue ex
          error_type = ex.class.name
        end
        
        # Evaluate result
        if test[:should_pass]
          if client_succeeded
            puts "✅ PASS (client handled correctly)"
            passed += 1
          else
            puts "❌ FAIL (client rejected valid scenario with #{error_type})"
            failed += 1
          end
        else
          if client_succeeded
            puts "❌ FAIL (client accepted invalid scenario)"
            failed += 1
          else
            puts "✅ PASS (client correctly rejected with #{error_type})"
            passed += 1
          end
        end
        
      ensure
        # Clean up
        Process.run("docker", ["kill", container_name], output: :pipe, error: :pipe)
      end
    end
    
    puts "\n" + "=" * 60
    puts "Results: #{passed} passed, #{failed} failed"
    puts "=" * 60
    
    # We expect some failures to prove the harness works
    failed.should be > 0
  end
end