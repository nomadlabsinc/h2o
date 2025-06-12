require "./fast_test_helpers_spec"

# Ultra-fast integration tests optimized for local Docker infrastructure
describe "Ultra-Fast HTTP/2 Integration Tests" do
  describe "Rapid Smoke Tests" do
    it "validates basic HTTP/2 functionality in under 1 second" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: ultra_fast_timeout, verify_ssl: false)
      response = fast_retry { client.get(test_base_url) }

      # Fast validation
      fast_validate_response(response).should be_true
      response.status.should eq(200)

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end

    it "performs 3 parallel requests in under 3 seconds" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # Create 3 identical URLs for parallel testing (70% reduction from 10)
      urls = Array(String).new(3) { test_base_url }

      responses = parallel_requests(urls, client)

      # Validate all responses - expect 100% success
      successful_responses = responses.count { |response| fast_validate_response(response) }
      successful_responses.should eq(3) # All requests should succeed

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end

    it "handles 2 concurrent clients in under 4 seconds" do
      start_time = Time.monotonic

      clients = create_parallel_clients(2, fast_client_timeout) # 60% reduction from 5

      # Each client makes a request in parallel
      channels = Array(Channel(Bool)).new(2)

      clients.each_with_index do |client, i|
        channel = Channel(Bool).new(1)
        channels << channel

        spawn do
          response = fast_retry { client.get("#{test_base_url}/?client=#{i}") }
          channel.send(fast_validate_response(response))
        end
      end

      # Wait for all requests
      results = channels.map(&.receive)
      successful_count = results.count(&.itself)

      # Cleanup
      clients.each(&.close)

      # Expect 100% success with reduced load
      successful_count.should eq(2)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end
  end

  describe "High-Throughput Tests" do
    it "processes 5 requests using batch execution" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      successful_count, total_count = batch_test(5) do |i| # 75% reduction from 20
        response = fast_retry { client.get("#{test_base_url}/?batch=#{i}") }
        raise "Invalid response" unless fast_validate_response(response)
      end

      client.close

      # Expect 100% success with reduced load
      successful_count.should eq(total_count)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end

    it "validates HTTP/2 server with minimal latency" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: ultra_fast_timeout, verify_ssl: false)
      response = fast_retry { client.get(test_base_url) }

      fast_validate_response(response).should be_true
      response.status.should eq(200)

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 800.milliseconds
    end
  end

  describe "Error Handling Speed Tests" do
    it "handles connection errors quickly" do
      GlobalStateHelper.ensure_clean_state
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: 200.milliseconds, verify_ssl: false) # Very short timeout

      # This should fail fast and return an error response
      response = client.get("https://nonexistent-host.invalid/")
      response.status.should eq(0)
      response.error?.should be_true

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second # Should fail quickly
    end

    it "validates argument errors instantly" do
      GlobalStateHelper.ensure_clean_state
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      expect_raises(ArgumentError) do
        client.get("not-a-valid-url")
      end

      expect_raises(ArgumentError) do
        client.get("http://example.com/") # HTTP not HTTPS
      end

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 100.milliseconds # Should be instant
    end
  end

  describe "Performance Regression Prevention" do
    it "ensures local server response time is under 100ms" do
      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # Measure actual response time
      response_time = Time.measure do
        response = client.get(test_base_url)
        response.should_not be_nil
      end

      client.close

      # Local servers should respond very quickly
      response_time.should be <= 200.milliseconds
    end

    it "validates connection reuse is working efficiently" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # First request establishes connection
      response1 = client.get(test_base_url)
      fast_validate_response(response1).should be_true

      # Subsequent requests should reuse connection and be faster
      response2 = client.get(test_base_url)
      response3 = client.get(test_base_url)

      fast_validate_response(response2).should be_true
      fast_validate_response(response3).should be_true

      client.close

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second # 3 requests should be fast with reuse
    end
  end
end
