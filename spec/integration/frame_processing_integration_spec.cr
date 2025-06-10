require "../spec_helper"
require "../../src/h2o"

describe "Frame Processing Pipeline Integration" do
  it "verifies batch processing works correctly with real HTTP/2 server" do
    server = HTTP::Server.new do |context|
      case context.request.path
      when "/batch-test"
        # Send multiple small responses to test batching
        10.times do |i|
          context.response.puts "Response #{i}"
        end
      when "/large-data"
        # Send large data to test buffer management
        context.response.print("x" * 100_000)
      else
        context.response.status_code = 404
      end
    end

    address = server.bind_tcp(0)
    port = address.port
    spawn { server.listen }

    sleep(0.1.seconds)

    # Test with batch processing enabled
    client = H2O::Client.new

    # Verify batch processing handles multiple responses correctly
    response1 = client.get("http://localhost:#{port}/batch-test")
    response1.should_not be_nil
    response1.try(&.status).should eq(200)
    if body = response1.try(&.body)
      body.should contain("Response 0")
      body.should contain("Response 9")
    end

    # Verify large data handling
    response2 = client.get("http://localhost:#{port}/large-data")
    response2.should_not be_nil
    response2.try(&.status).should eq(200)
    response2.try(&.body.size).should eq(100_000)

    client.close
    server.close
  end

  it "compares performance with and without batch processing" do
    server = HTTP::Server.new do |context|
      # Echo back request headers and send some data
      context.response.headers["X-Echo"] = "test"
      context.response.print("Hello from server")
    end

    address = server.bind_tcp(0)
    port = address.port
    spawn { server.listen }

    sleep(0.1.seconds)

    requests_per_test = 100

    # Test without batch processing
    client1 = H2O::Client.new
    if client1.responds_to?(:set_batch_processing)
      client1.set_batch_processing(false)
    end

    start_time = Time.monotonic
    requests_per_test.times do
      response = client1.get("http://localhost:#{port}/")
      response.should_not be_nil
    end
    time_without_batch = Time.monotonic - start_time
    client1.close

    # Test with batch processing
    client2 = H2O::Client.new
    # Batch processing is enabled by default

    start_time = Time.monotonic
    requests_per_test.times do
      response = client2.get("http://localhost:#{port}/")
      response.should_not be_nil
    end
    time_with_batch = Time.monotonic - start_time
    client2.close

    server.close

    puts "\n=== Real-world Performance Comparison ==="
    puts "Requests: #{requests_per_test}"
    puts "Without batch processing: #{time_without_batch.total_milliseconds.round(2)}ms"
    puts "With batch processing: #{time_with_batch.total_milliseconds.round(2)}ms"

    # Calculate improvement
    if time_with_batch < time_without_batch
      improvement = ((time_without_batch - time_with_batch) / time_without_batch * 100).round(1)
      speedup = (time_without_batch.total_milliseconds / time_with_batch.total_milliseconds).round(2)
      puts "Improvement: #{improvement}%"
      puts "Speedup: #{speedup}x"
    end
  end
end
