require "../../spec_helper"

# Regression tests for GitHub Issue #40: HTTP/2 requests timeout after 5 seconds and return nil instead of response
describe "Stream timeout regression tests" do
  describe "H2O::Stream#await_response" do
    it "uses 5 second timeout (current implementation)" do
      stream = H2O::Stream.new(1_u32)

      start_time = Time.monotonic
      result = stream.await_response
      end_time = Time.monotonic

      elapsed = end_time - start_time
      # Should timeout around 5 seconds with current implementation
      elapsed.should be_close(5.seconds, 200.milliseconds)
      result.should be_nil
    end

    it "returns nil on timeout instead of raising exception" do
      stream = H2O::Stream.new(1_u32)

      result = stream.await_response
      result.should be_nil
    end

    it "returns nil when channel is closed" do
      stream = H2O::Stream.new(1_u32)
      stream.response_channel.close

      result = stream.await_response
      result.should be_nil
    end

    it "returns response when available within timeout" do
      stream = H2O::Stream.new(1_u32)
      response = H2O::Response.new(200)

      spawn do
        sleep 10.milliseconds
        stream.response_channel.send(response)
      end

      result = stream.await_response
      result.should eq(response)
      result.should_not be_nil
      if final_result = result
        final_result.status.should eq(200)
      end
    end
  end

  describe "Client configuration timeout behavior" do
    it "respects client timeout setting for HTTP/2 requests" do
      custom_timeout = 3.seconds
      client = H2O::Client.new(timeout: custom_timeout)

      # Verify that the client stores the timeout correctly
      client.timeout.should eq(custom_timeout)
    end

    it "uses default timeout when no timeout specified" do
      client = H2O::Client.new

      # Should use the default timeout (1 second)
      client.timeout.should eq(1.seconds)
    end
  end
end
