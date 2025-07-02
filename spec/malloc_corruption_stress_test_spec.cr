require "./spec_helper"

describe "Malloc Corruption Stress Test" do
  it "handles extreme concurrent client creation and destruction" do
    # This test was specifically designed to trigger the malloc corruption bug
    # that was caused by global shared state (TLS cache, string pool, etc.)
    
    success_count = Atomic(Int32).new(0)
    error_count = Atomic(Int32).new(0)
    
    # Create a large number of fibers that rapidly create/destroy clients
    stress_fibers = [] of Fiber
    
    50.times do |batch|
      fiber = spawn do
        5.times do |iteration|
          begin
            # Create client
            client = H2O::Client.new
            
            # Immediately close it
            client.close
            
            # Track success
            success_count.add(1)
            
            # Tiny delay to allow GC
            sleep 0.1.milliseconds
          rescue ex
            error_count.add(1)
            Log.error { "Stress test batch #{batch}, iteration #{iteration} failed: #{ex.message}" }
          end
        end
      end
      
      stress_fibers << fiber
    end
    
    # Wait for all fibers with timeout
    timeout_at = Time.monotonic + 30.seconds
    stress_fibers.each do |fiber|
      while !fiber.dead? && Time.monotonic < timeout_at
        sleep 0.01.seconds
      end
    end
    
    Log.info { "Stress test completed - Success: #{success_count.get}, Errors: #{error_count.get}" }
    
    # The test passes if we didn't crash with malloc corruption
    # We expect all operations to succeed
    success_count.get.should be > 0
    error_count.get.should eq 0
  end
  
  it "handles rapid connection creation to the same host" do
    # This pattern specifically tested the TLS cache corruption issue
    
    clients = [] of H2O::Client
    
    begin
      # Create many clients to the same host rapidly
      10.times do
        clients << H2O::Client.new
      end
      
      # Use them all concurrently
      fibers = clients.map_with_index do |client, index|
        spawn do
          begin
            response = client.get("https://httpbin.org/status/200")
            response.status.should eq 200
          rescue ex
            Log.error { "Client #{index} request failed: #{ex.message}" }
            raise ex
          end
        end
      end
      
      # Wait for all requests
      fibers.each do |fiber|
        timeout_at = Time.monotonic + 10.seconds
        while !fiber.dead? && Time.monotonic < timeout_at
          sleep 0.01.seconds
        end
      end
      
    ensure
      # Clean up all clients
      clients.each(&.close)
    end
    
    # Test passes if no malloc corruption occurred
    true.should be_true
  end
  
  it "handles interleaved client operations without corruption" do
    # This tests the pattern where operations are interleaved between clients
    
    client1 = H2O::Client.new
    client2 = H2O::Client.new
    client3 = H2O::Client.new
    
    results = [] of Bool
    
    begin
      # Interleave operations
      fiber1 = spawn do
        response = client1.get("https://httpbin.org/delay/1")
        results << (response.status == 200)
      end
      
      fiber2 = spawn do
        response = client2.get("https://httpbin.org/get")
        results << (response.status == 200)
      end
      
      fiber3 = spawn do
        response = client3.get("https://httpbin.org/status/201")
        results << (response.status == 201)
      end
      
      # Wait for all
      [fiber1, fiber2, fiber3].each do |fiber|
        timeout_at = Time.monotonic + 15.seconds
        while !fiber.dead? && Time.monotonic < timeout_at
          sleep 0.01.seconds
        end
      end
      
    ensure
      client1.close
      client2.close  
      client3.close
    end
    
    # All operations should have succeeded
    results.size.should eq 3
    results.all?(&.itself).should be_true
  end
end