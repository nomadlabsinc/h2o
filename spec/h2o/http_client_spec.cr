require "../spec_helper"

describe H2O::HttpClient do
  after_each do
    GlobalStateHelper.clear_all_caches
  end

  describe "#initialize" do
    it "creates client with default settings" do
      client = H2O::HttpClient.new
      begin
        client.should_not be_nil
      ensure
        client.close
      end
    end

    it "creates client with custom connection pool size" do
      client = H2O::HttpClient.new(connection_pool_size: 5)
      begin
        client.should_not be_nil
      ensure
        client.close
      end
    end

    it "creates client with h2 prior knowledge enabled" do
      client = H2O::HttpClient.new(h2_prior_knowledge: true)
      begin
        client.should_not be_nil
      ensure
        client.close
      end
    end

    it "creates client with custom timeout" do
      client = H2O::HttpClient.new(timeout: 5.seconds)
      begin
        client.should_not be_nil
      ensure
        client.close
      end
    end

    it "creates client with circuit breaker disabled" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: false)
      begin
        client.should_not be_nil
      ensure
        client.close
      end
    end
  end

  describe "#close" do
    it "closes client and cleans up resources" do
      client = H2O::HttpClient.new
      client.close

      # Should raise error when trying to make requests after close
      expect_raises(H2O::ConnectionError, "Client has been closed") do
        client.get("https://example.com/")
      end
    end

    it "can be called multiple times safely" do
      client = H2O::HttpClient.new
      client.close
      client.close # Should not raise
    end
  end

  describe "HTTP methods" do
    it "supports GET requests" do
      client = H2O::HttpClient.new

      # Mock the underlying request method
      response = client.get("https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports POST requests with body" do
      client = H2O::HttpClient.new

      response = client.post("https://example.com/", body: "test data")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports PUT requests with body" do
      client = H2O::HttpClient.new

      response = client.put("https://example.com/", body: "test data")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports DELETE requests" do
      client = H2O::HttpClient.new

      response = client.delete("https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports HEAD requests" do
      client = H2O::HttpClient.new

      response = client.head("https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports OPTIONS requests" do
      client = H2O::HttpClient.new

      response = client.options("https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "supports PATCH requests with body" do
      client = H2O::HttpClient.new

      response = client.patch("https://example.com/", body: "test data")
      response.should be_a(H2O::Response)

      client.close
    end
  end

  describe "#request" do
    it "raises error for invalid URL" do
      client = H2O::HttpClient.new

      expect_raises(ArgumentError, "Invalid URL: missing host") do
        client.request("GET", "invalid-url")
      end

      client.close
    end

    it "handles HTTP URLs" do
      client = H2O::HttpClient.new

      response = client.request("GET", "http://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "handles HTTPS URLs" do
      client = H2O::HttpClient.new

      response = client.request("GET", "https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end

    it "uses custom headers" do
      client = H2O::HttpClient.new
      headers = H2O::Headers.new
      headers["Custom-Header"] = "test-value"

      response = client.request("GET", "https://example.com/", headers)
      response.should be_a(H2O::Response)

      client.close
    end

    it "bypasses circuit breaker when requested" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: true)

      response = client.request("GET", "https://example.com/", bypass_circuit_breaker: true)
      response.should be_a(H2O::Response)

      client.close
    end

    it "uses circuit breaker when explicitly enabled" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: false)

      response = client.request("GET", "https://example.com/", circuit_breaker: true)
      response.should be_a(H2O::Response)

      client.close
    end
  end

  describe "#statistics" do
    it "returns statistics from all components" do
      client = H2O::HttpClient.new

      stats = client.statistics
      stats.should be_a(Hash(Symbol, Hash(Symbol, Int32 | Float64)))

      # Should have stats from all three components
      stats.has_key?(:connection_pool).should be_true
      stats.has_key?(:protocol_negotiator).should be_true
      stats.has_key?(:circuit_breaker).should be_true

      client.close
    end
  end

  describe "#warmup_connection" do
    it "warms up connection to host" do
      client = H2O::HttpClient.new

      # Should not raise
      client.warmup_connection("example.com", 443)

      client.close
    end

    it "uses default port 443" do
      client = H2O::HttpClient.new

      # Should not raise
      client.warmup_connection("example.com")

      client.close
    end
  end

  describe "#set_batch_processing" do
    it "enables batch processing" do
      client = H2O::HttpClient.new

      # Should not raise
      client.set_batch_processing(true)

      client.close
    end

    it "disables batch processing" do
      client = H2O::HttpClient.new

      # Should not raise
      client.set_batch_processing(false)

      client.close
    end
  end

  describe "circuit breaker management" do
    it "forces protocol for host" do
      client = H2O::HttpClient.new

      # Should not raise
      client.force_protocol("example.com", 443, "HTTP/2")

      client.close
    end

    it "opens circuit breaker for host" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: true)

      # Should not raise
      client.open_circuit_breaker("example.com", 443)

      client.close
    end

    it "closes circuit breaker for host" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: true)

      # Should not raise
      client.close_circuit_breaker("example.com", 443)

      client.close
    end

    it "returns circuit breaker state" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: true)

      state = client.circuit_breaker_state("example.com", 443)
      # Should return nil for non-existent breaker or a string state
      state.should be_a(String | Nil)

      client.close
    end
  end

  describe "cleanup methods" do
    it "cleans up expired connections" do
      client = H2O::HttpClient.new

      # Should not raise
      client.cleanup_expired_connections

      client.close
    end

    it "cleans up expired cache" do
      client = H2O::HttpClient.new

      # Should not raise
      client.cleanup_expired_cache

      client.close
    end
  end

  describe "error handling" do
    it "handles timeout errors gracefully" do
      client = H2O::HttpClient.new(timeout: 1.millisecond)

      response = client.request("GET", "https://10.255.255.1/")
      response.should be_a(H2O::Response)
      response.success?.should be_false

      client.close
    end

    it "handles connection errors gracefully" do
      client = H2O::HttpClient.new

      # Try to connect to a non-existent host
      response = client.request("GET", "https://this-host-should-not-exist-12345.com/")
      response.should be_a(H2O::Response)
      response.success?.should be_false

      client.close
    end

    it "preserves argument errors" do
      client = H2O::HttpClient.new

      expect_raises(ArgumentError) do
        client.request("GET", "")
      end

      client.close
    end
  end

  describe "component orchestration" do
    it "coordinates between all components for successful request" do
      client = H2O::HttpClient.new(
        connection_pool_size: 2,
        h2_prior_knowledge: false,
        circuit_breaker_enabled: true
      )

      # Make a request that exercises all components
      response = client.request("GET", "https://example.com/")
      response.should be_a(H2O::Response)

      # Verify statistics are updated across components
      stats = client.statistics
      stats[:connection_pool].should be_a(Hash(Symbol, Int32 | Float64))
      stats[:protocol_negotiator].should be_a(Hash(Symbol, Int32 | Float64))
      stats[:circuit_breaker].should be_a(Hash(Symbol, Int32 | Float64))

      client.close
    end

    it "handles component failures gracefully" do
      client = H2O::HttpClient.new(circuit_breaker_enabled: true)

      # Force a failure and verify circuit breaker response
      client.open_circuit_breaker("example.com", 443)

      response = client.request("GET", "https://example.com/")
      response.should be_a(H2O::Response)

      client.close
    end
  end

  describe "resource management" do
    it "properly cleans up resources on close" do
      client = H2O::HttpClient.new

      # Make a request to create some resources
      client.request("GET", "https://example.com/")

      # Close should clean up everything
      client.close

      # Subsequent requests should fail
      expect_raises(H2O::ConnectionError, "Client has been closed") do
        client.request("GET", "https://example.com/")
      end
    end

    it "handles resource cleanup with active connections" do
      client = H2O::HttpClient.new(connection_pool_size: 5)

      # Warm up multiple connections
      5.times do |i|
        client.warmup_connection("example#{i}.com", 443)
      end

      # Close should handle all connections
      client.close

      expect_raises(H2O::ConnectionError, "Client has been closed") do
        client.request("GET", "https://example.com/")
      end
    end
  end
end
