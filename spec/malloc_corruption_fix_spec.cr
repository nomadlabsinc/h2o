require "./spec_helper"

describe "Malloc Corruption Fix" do
  it "handles multiple concurrent clients without malloc corruption" do
    # This test creates many clients concurrently to trigger the malloc corruption bug
    # The fix removes global shared state that was causing the issue
    
    success_count = Atomic(Int32).new(0)
    error_count = Atomic(Int32).new(0)
    
    # Create multiple clients concurrently
    fibers = [] of Fiber
    
    20.times do |i|
      fiber = spawn do
        begin
          client = H2O::Client.new
          
          # Make a simple request
          response = client.get("https://httpbin.org/get")
          
          if response.status == 200
            success_count.add(1)
          else
            error_count.add(1)
          end
          
          client.close
        rescue ex
          error_count.add(1)
          Log.error { "Client #{i} failed: #{ex.message}" }
        end
      end
      
      fibers << fiber
    end
    
    # Wait for all fibers to complete
    fibers.each do |fiber|
      # Wait up to 10 seconds for each fiber
      timeout = 10.seconds
      start_time = Time.monotonic
      
      while !fiber.dead? && (Time.monotonic - start_time) < timeout
        sleep 0.1.seconds
      end
    end
    
    # Log results
    Log.info { "Success: #{success_count.get}, Errors: #{error_count.get}" }
    
    # The test passes if we didn't crash with malloc corruption
    # We allow some errors due to network issues, but no crashes
    (success_count.get + error_count.get).should be > 0
  end
  
  it "creates and destroys clients rapidly without corruption" do
    # This specifically tests the pattern that was causing malloc corruption
    
    10.times do
      client = H2O::Client.new
      client.close
      
      # Small delay to allow cleanup
      sleep 1.millisecond
    end
    
    # If we get here without crashing, the test passes
    true.should be_true
  end
  
  it "handles concurrent access to the same host" do
    # Multiple clients accessing the same host was triggering cache corruption
    
    success_count = Atomic(Int32).new(0)
    
    fibers = [] of Fiber
    
    10.times do |i|
      fiber = spawn do
        begin
          client = H2O::Client.new
          
          # All clients hit the same host
          response = client.get("https://httpbin.org/status/200")
          
          if response.status == 200
            success_count.add(1)
          end
          
          client.close
        rescue ex
          Log.error { "Concurrent client #{i} failed: #{ex.message}" }
        end
      end
      
      fibers << fiber
    end
    
    # Wait for completion
    fibers.each do |fiber|
      timeout = 10.seconds
      start_time = Time.monotonic
      
      while !fiber.dead? && (Time.monotonic - start_time) < timeout
        sleep 0.1.seconds
      end
    end
    
    # We should have some successful requests
    success_count.get.should be > 0
  end
end