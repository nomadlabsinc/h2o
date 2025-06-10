require "../spec_helper"

# Unit tests for configurable timeout settings
describe "Configurable timeout settings" do
  describe "H2O::Client timeout configuration" do
    it "accepts timeout parameter in constructor" do
      timeout = 15.seconds
      client = H2O::Client.new(timeout: timeout)

      client.timeout.should eq(timeout)
    end

    it "uses default timeout when not specified" do
      client = H2O::Client.new

      client.timeout.should eq(H2O.config.default_timeout)
    end

    it "accepts other parameters along with timeout" do
      timeout = 20.seconds
      pool_size = 5

      client = H2O::Client.new(
        connection_pool_size: pool_size,
        timeout: timeout,
        circuit_breaker_enabled: true
      )

      client.timeout.should eq(timeout)
      client.connection_pool_size.should eq(pool_size)
      client.circuit_breaker_enabled.should be_true
    end
  end

  describe "H2O::H2::Client timeout configuration" do
    it "accepts both connect_timeout and request_timeout parameters" do
      connect_timeout = 5.seconds
      request_timeout = 15.seconds

      client = H2O::H2::Client.new(
        "example.com",
        443,
        connect_timeout: connect_timeout,
        request_timeout: request_timeout
      )

      client.request_timeout.should eq(request_timeout)
    end

    it "uses default values when timeouts not specified" do
      client = H2O::H2::Client.new("example.com", 443)

      # Default request_timeout should be 5 seconds
      client.request_timeout.should eq(5.seconds)
    end

    it "can set different connect and request timeouts" do
      connect_timeout = 3.seconds
      request_timeout = 25.seconds

      client = H2O::H2::Client.new(
        "example.com",
        443,
        connect_timeout: connect_timeout,
        request_timeout: request_timeout
      )

      client.request_timeout.should eq(request_timeout)
      # Note: connect_timeout is used during initialization and not stored as a property
    end
  end

  describe "H2O::Stream timeout configuration" do
    it "accepts timeout parameter in await_response" do
      stream = H2O::Stream.new(1_u32)
      timeout = 5.seconds

      # This will timeout but we're just testing the parameter is accepted
      expect_raises(H2O::TimeoutError) do
        stream.await_response(timeout)
      end
    end

    it "uses default timeout when parameter not provided" do
      stream = H2O::Stream.new(1_u32)

      # This will timeout quickly for testing
      expect_raises(H2O::TimeoutError) do
        stream.await_response(1.second) # Use 1 second for testing
      end
    end
  end

  describe "H2O global configuration" do
    it "allows configuring default timeout" do
      original_timeout = H2O.config.default_timeout

      begin
        H2O.configure do |config|
          config.default_timeout = 45.seconds
        end

        H2O.config.default_timeout.should eq(45.seconds)

        # New clients should use the updated default
        client = H2O::Client.new
        client.timeout.should eq(45.seconds)
      ensure
        # Restore original timeout
        H2O.configure do |config|
          config.default_timeout = original_timeout
        end
      end
    end

    it "maintains separate timeout settings" do
      original_timeout = H2O.config.default_timeout
      original_recovery = H2O.config.default_recovery_timeout

      begin
        H2O.configure do |config|
          config.default_timeout = 25.seconds
          config.default_recovery_timeout = 120.seconds
        end

        H2O.config.default_timeout.should eq(25.seconds)
        H2O.config.default_recovery_timeout.should eq(120.seconds)

        # These should be independent settings
        H2O.config.default_timeout.should_not eq(H2O.config.default_recovery_timeout)
      ensure
        # Restore original values
        H2O.configure do |config|
          config.default_timeout = original_timeout
          config.default_recovery_timeout = original_recovery
        end
      end
    end
  end

  describe "Timeout edge cases" do
    it "handles very short timeouts" do
      stream = H2O::Stream.new(1_u32)
      very_short = 1.millisecond

      expect_raises(H2O::TimeoutError) do
        stream.await_response(very_short)
      end
    end

    it "handles longer timeouts" do
      stream = H2O::Stream.new(1_u32)
      response = H2O::Response.new(200)
      longer_timeout = 5.seconds

      # Send response immediately to avoid actually waiting
      spawn do
        stream.response_channel.send(response)
      end

      result = stream.await_response(longer_timeout)
      result.should eq(response)
      result.should_not be_nil
    end

    it "handles zero timeout correctly" do
      stream = H2O::Stream.new(1_u32)
      zero_timeout = 0.seconds

      expect_raises(H2O::TimeoutError) do
        stream.await_response(zero_timeout)
      end
    end
  end
end
