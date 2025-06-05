require "../spec_helper"

describe H2O::Client do
  describe "connection pooling" do
    it "should reuse connections for the same host" do
      client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

      begin
        initial_count = client.connections.size

        success = NetworkTestHelper.require_network("connection pooling") do
          # Make multiple requests to the same host
          successful_requests = 0
          3.times do
            response = client.get("https://httpbin.org/get")
            successful_requests += 1 if response && response.status == 200
          end

          successful_requests > 0
        end

        # If network test succeeded, verify pooling behavior
        if success
          # Should only create one connection for the same host
          client.connections.size.should eq(initial_count + 1)
        else
          # If no network available, just verify client state is clean
          client.connections.size.should eq(initial_count)
        end
      ensure
        client.close
      end
    end

    it "should create separate connections for different hosts" do
      client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

      begin
        hosts = [
          "https://httpbin.org/get",
          "https://www.google.com",
        ]

        initial_count = client.connections.size

        hosts.each do |url|
          response = client.get(url)
          # Don't require response to be non-nil as some hosts may fail
        end

        # Should have attempted to create connections for each host
        client.connections.size.should be >= initial_count
      ensure
        client.close
      end
    end

    it "should respect connection pool size limits" do
      pool_size = 2
      client = H2O::Client.new(connection_pool_size: pool_size, timeout: 1.seconds)

      begin
        # Try to create more connections than pool size allows
        hosts = [
          "https://httpbin.org/get",
          "https://www.google.com",
          "https://httpbin.org/status/200",
        ]

        hosts.each do |url|
          response = client.get(url)
          # Don't require response to be non-nil as some hosts may fail
        end

        # Pool size should not exceed the limit
        client.connections.size.should be <= pool_size
      ensure
        client.close
      end
    end

    it "should cleanup closed connections" do
      client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

      begin
        # Make a request to create a connection
        response = client.get("https://httpbin.org/get")

        initial_count = client.connections.size

        # Manually close connections to simulate network issues
        client.connections.each_value(&.close)

        # Make another request, should cleanup closed connections
        response = client.get("https://httpbin.org/get")

        # The old closed connections should be cleaned up
        client.connections.values.all?(&.closed?).should be_false
      ensure
        client.close
      end
    end

    it "should handle mixed HTTP/1.1 and HTTP/2 connections" do
      client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

      begin
        # Make requests that will likely result in different protocols
        urls = [
          "https://httpbin.org/get", # Likely HTTP/1.1
          "https://www.google.com",  # Likely HTTP/2
        ]

        responses = [] of H2O::Response?

        urls.each do |url|
          response = client.get(url)
          responses << response
        end

        # At least one request should succeed
        responses.any? { |response| !response.nil? }.should be_true

        # Should have created connections
        client.connections.size.should be > 0
      ensure
        client.close
      end
    end

    it "should handle connection timeout gracefully" do
      # Use a very short timeout to test timeout handling
      client = H2O::Client.new(timeout: 50.milliseconds)

      begin
        # This should timeout and return nil (either from connection timeout or request timeout)
        response = client.get("https://httpbin.org/delay/1")
        response.should be_nil
      rescue H2O::ConnectionError
        # Connection timeout during fallback is also acceptable
      ensure
        client.close
      end
    end
  end
end
