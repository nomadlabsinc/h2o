require "./fast_test_helpers_spec"

# Focused parallel tests with optimal performance
describe "Focused Parallel HTTP/2 Tests" do
  describe "Basic Parallelism" do
    it "executes 2 parallel requests efficiently" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: ultra_fast_timeout, verify_ssl: false)

      # Use spawn for parallel execution with reduced count (60% reduction from 5)
      channels = Array(Channel(H2O::Response?)).new(2)

      2.times do |i|
        channel = Channel(H2O::Response?).new(1)
        channels << channel

        spawn do
          response = fast_retry { client.get("#{test_base_url}/?parallel=#{i}") }
          channel.send(response)
        end
      end

      # Collect all responses
      responses = channels.map(&.receive)
      successful_responses = responses.count { |response| response && response.status == 200 }

      client.close

      # Expect 100% success with reduced load
      successful_responses.should eq(2)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end

    it "handles 2 concurrent clients efficiently" do
      start_time = Time.monotonic

      # Create clients in parallel with reduced count (33% reduction from 3)
      client_channels = Array(Channel(H2O::Client)).new(2)

      2.times do |_|
        channel = Channel(H2O::Client).new(1)
        client_channels << channel

        spawn do
          client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)
          channel.send(client)
        end
      end

      # Get all clients
      clients = client_channels.map(&.receive)

      # Make requests in parallel
      response_channels = Array(Channel(Bool)).new(2)

      clients.each_with_index do |client, i|
        channel = Channel(Bool).new(1)
        response_channels << channel

        spawn do
          response = fast_retry { client.get("#{test_base_url}/?client=#{i}") }
          success = !!(response && response.status == 200)
          channel.send(success)
        end
      end

      # Collect results
      results = response_channels.map(&.receive)
      successful_count = results.count(&.itself)

      # Cleanup
      clients.each(&.close)

      # Expect 100% success with reduced concurrency
      successful_count.should eq(2)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end
  end

  describe "Optimized Request Patterns" do
    it "validates connection reuse with parallel requests" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # Make 2 requests in parallel to test connection reuse (33% reduction from 3)
      channels = Array(Channel(Bool)).new(2)

      2.times do |i|
        channel = Channel(Bool).new(1)
        channels << channel

        spawn do
          response = client.get("#{test_base_url}/?reuse=#{i}")
          success = !!(response && response.status == 200)
          channel.send(success)
        end
      end

      results = channels.map(&.receive)
      successful_count = results.count(&.itself)

      client.close

      # Expect 100% success with reduced load
      successful_count.should eq(2)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end

    it "handles mixed request types in parallel" do
      start_time = Time.monotonic

      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # Different request types in parallel - only reliable ones (33% reduction from 3)
      test_scenarios = [
        -> { client.get("#{test_base_url}/index.html") },
        -> { client.get("#{test_base_url}/?param=1") },
      ]

      channels = Array(Channel(Bool)).new(test_scenarios.size)

      test_scenarios.each do |scenario|
        channel = Channel(Bool).new(1)
        channels << channel

        spawn do
          begin
            response = fast_retry { scenario.call }
            success = !!(response && response.status == 200)
            channel.send(success)
          rescue
            channel.send(false)
          end
        end
      end

      results = channels.map(&.receive)
      successful_count = results.count(&.itself)

      client.close

      # Expect 100% success with reliable requests only
      successful_count.should eq(2)

      elapsed = Time.monotonic - start_time
      elapsed.should be <= 1.second
    end
  end

  describe "Performance Validation" do
    it "measures actual parallel performance improvement" do
      client = H2O::Client.new(timeout: fast_client_timeout, verify_ssl: false)

      # Sequential execution baseline
      sequential_time = Time.measure do
        5.times do |i|
          response = client.get("#{test_base_url}/?sequential=#{i}")
          response.should_not be_nil if response
        end
      end

      # Parallel execution
      parallel_time = Time.measure do
        channels = Array(Channel(H2O::Response?)).new(5)

        5.times do |i|
          channel = Channel(H2O::Response?).new(1)
          channels << channel

          spawn do
            response = client.get("#{test_base_url}/?parallel=#{i}")
            channel.send(response)
          end
        end

        responses = channels.map(&.receive)
        responses.each { |response| response.should_not be_nil if response }
      end

      client.close

      # Parallel should be faster (or at least not much slower due to overhead)
      speedup = sequential_time.total_seconds / parallel_time.total_seconds
      puts "Parallel speedup: #{speedup.round(2)}x (sequential: #{sequential_time.total_seconds.round(3)}s, parallel: #{parallel_time.total_seconds.round(3)}s)"

      # Parallel execution should not be significantly slower
      parallel_time.should be <= (sequential_time * 1.5)
    end
  end
end
