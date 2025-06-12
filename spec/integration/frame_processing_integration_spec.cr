require "../spec_helper"
require "../../src/h2o"

describe "Frame Processing Pipeline Integration" do
  it "verifies batch processing works correctly with real HTTP/2 server" do
    # Test with Docker HTTPS server instead of creating local HTTP server
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    # Verify basic request handling works
    response1 = client.get(TestConfig.http2_url)
    response1.should_not be_nil
    response1.status.should eq(200)
    response1.body.should contain("Nginx HTTP/2 test server")

    # Verify multiple requests work (tests connection reuse and frame processing)
    response2 = client.get("#{TestConfig.http2_url}/?test=1")
    response2.should_not be_nil
    response2.status.should eq(200)
    response2.body.should contain("Nginx HTTP/2 test server")

    # Verify headers endpoint works (tests different frame types)
    response3 = client.get("#{TestConfig.http2_url}/headers")
    response3.should_not be_nil
    response3.status.should eq(200)
    response3.body.should contain("headers")

    client.close
  end

  it "compares performance with different request patterns" do
    # Test with Docker HTTPS server for reliable performance comparison
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    requests_per_test = 10 # Reduced for reliability

    # Test sequential requests
    start_time = Time.monotonic
    requests_per_test.times do |i|
      response = client.get("#{TestConfig.http2_url}/?req=#{i}")
      response.status.should eq(200)
    end
    sequential_time = Time.monotonic - start_time

    # Test parallel requests
    start_time = Time.monotonic
    channels = Array(Channel(H2O::Response)).new(requests_per_test)

    requests_per_test.times do |i|
      channel = Channel(H2O::Response).new(1)
      channels << channel
      spawn do
        response = client.get("#{TestConfig.http2_url}/?parallel=#{i}")
        channel.send(response)
      end
    end

    responses = channels.map(&.receive)
    parallel_time = Time.monotonic - start_time

    # Verify all parallel requests succeeded
    responses.each(&.status.should(eq(200)))

    client.close

    puts "\n=== HTTP/2 Performance Comparison ==="
    puts "Requests: #{requests_per_test}"
    puts "Sequential: #{sequential_time.total_milliseconds.round(2)}ms"
    puts "Parallel: #{parallel_time.total_milliseconds.round(2)}ms"

    # Parallel should be faster or at least not much slower
    parallel_time.should be <= (sequential_time * 1.5)
  end
end
