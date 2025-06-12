require "../../spec_helper"

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

  # Note: H2O::H2::Client timeout configuration tests moved to integration tests
  # due to network connection requirements during client initialization

  describe "H2O::Stream timeout configuration" do
    it "accepts timeout parameter in await_response" do
      stream = H2O::Stream.new(1_u32)
      timeout = 1.second

      # This will timeout and should return nil
      start_time = Time.monotonic
      result = stream.await_response(timeout)
      end_time = Time.monotonic

      result.should be_nil
      elapsed = end_time - start_time
      elapsed.should be_close(timeout, 200.milliseconds)
    end

    it "uses default timeout when parameter not provided" do
      stream = H2O::Stream.new(1_u32)

      # This will timeout and should return nil after default timeout (5s)
      start_time = Time.monotonic
      result = stream.await_response
      end_time = Time.monotonic

      result.should be_nil
      elapsed = end_time - start_time
      elapsed.should be_close(5.seconds, 200.milliseconds)
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
      very_short = 100.milliseconds

      start_time = Time.monotonic
      result = stream.await_response(very_short)
      end_time = Time.monotonic

      result.should be_nil
      elapsed = end_time - start_time
      elapsed.should be_close(very_short, 50.milliseconds)
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

      # Zero timeout should return immediately with nil
      start_time = Time.monotonic
      result = stream.await_response(zero_timeout)
      end_time = Time.monotonic

      result.should be_nil
      elapsed = end_time - start_time
      elapsed.should be < 100.milliseconds # Should return very quickly
    end
  end
end
