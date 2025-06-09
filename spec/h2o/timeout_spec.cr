require "../spec_helper"

describe H2O::Timeout do
  describe ".execute" do
    it "returns result when operation completes within timeout" do
      result = H2O::Timeout(String).execute(1.second) do
        "success"
      end

      result.should eq("success")
    end

    it "returns nil when operation times out" do
      result = H2O::Timeout(String).execute(10.milliseconds) do
        sleep 20.milliseconds
        "should not reach here"
      end

      result.should be_nil
    end

    it "handles exceptions gracefully and returns nil" do
      result = H2O::Timeout(String).execute(1.second) do
        raise "test error"
        "should not reach here"
      end

      result.should be_nil
    end

    it "works with different return types" do
      int_result = H2O::Timeout(Int32).execute(1.second) do
        42
      end

      bool_result = H2O::Timeout(Bool).execute(1.second) do
        true
      end

      int_result.should eq(42)
      bool_result.should eq(true)
    end

    it "handles channel operations correctly" do
      channel = Channel(String).new(1)

      spawn do
        sleep 5.milliseconds
        channel.send("delayed message")
      end

      result = H2O::Timeout(String).execute(1.second) do
        channel.receive
      end

      result.should eq("delayed message")
    end

    it "times out channel operations that take too long" do
      channel = Channel(String).new(1)

      # Don't send anything to the channel
      result = H2O::Timeout(String).execute(10.milliseconds) do
        channel.receive
      end

      result.should be_nil
    end
  end

  describe ".execute!" do
    it "returns result when operation completes within timeout" do
      result = H2O::Timeout(String).execute!(1.second) do
        "success"
      end

      result.should eq("success")
    end

    it "raises TimeoutError when operation times out" do
      expect_raises(H2O::TimeoutError, /Operation timed out after/) do
        H2O::Timeout(String).execute!(10.milliseconds) do
          sleep 20.milliseconds
          "should not reach here"
        end
      end
    end

    it "propagates exceptions from the block" do
      expect_raises(Exception, "test error") do
        H2O::Timeout(String).execute!(1.second) do
          raise "test error"
          "should not reach here"
        end
      end
    end
  end

  describe ".execute_with_handler" do
    it "returns result when operation completes within timeout" do
      result = H2O::Timeout(String).execute_with_handler(1.second, -> { "timeout" }) do
        "success"
      end

      result.should eq("success")
    end

    it "calls timeout handler when operation times out" do
      result = H2O::Timeout(String).execute_with_handler(10.milliseconds, -> { "timeout" }) do
        sleep 20.milliseconds
        "should not reach here"
      end

      result.should eq("timeout")
    end

    it "calls timeout handler on exceptions" do
      result = H2O::Timeout(String).execute_with_handler(1.second, -> { "error" }) do
        raise "test error"
        "should not reach here"
      end

      result.should eq("error")
    end

    it "works with different return types from handler" do
      result = H2O::Timeout(String).execute_with_handler(10.milliseconds, -> { 404 }) do
        sleep 20.milliseconds
        "should not reach here"
      end

      result.should eq(404)
    end
  end

  describe "real-world scenarios" do
    it "handles HTTP response-like scenarios" do
      # Simulate HTTP response with timeout
      response_channel = Channel(String?).new(1)

      spawn do
        sleep 5.milliseconds
        response_channel.send("HTTP/2 200 OK")
      end

      result = H2O::Timeout(String?).execute(1.second) do
        response_channel.receive
      end

      result.should eq("HTTP/2 200 OK")
    end

    it "handles connection establishment timeouts" do
      # Simulate slow connection
      result = H2O::Timeout(Bool).execute_with_handler(10.milliseconds, -> { false }) do
        sleep 20.milliseconds # Simulate slow connection
        true
      end

      result.should eq(false)
    end

    it "handles fiber coordination scenarios" do
      # Simulate waiting for multiple fibers to finish
      fiber_done = Channel(Bool).new(3)

      3.times do |i|
        spawn do
          sleep ((i + 1) * 2).milliseconds
          fiber_done.send(true)
        end
      end

      result = H2O::Timeout(Bool).execute_with_handler(1.second, -> { false }) do
        3.times { fiber_done.receive }
        true
      end

      result.should eq(true)
    end

    it "properly handles cleanup in timeout scenarios" do
      cleanup_called = false

      result = H2O::Timeout(String).execute_with_handler(10.milliseconds, -> {
        cleanup_called = true
        "cleaned up"
      }) do
        sleep 20.milliseconds
        "should not reach"
      end

      result.should eq("cleaned up")
      cleanup_called.should be_true
    end
  end
end

describe H2O::TimeoutError do
  it "can be created with a message" do
    error = H2O::TimeoutError.new("test timeout")
    error.message.should eq("test timeout")
    error.should be_a(Exception)
  end

  it "inherits from Exception properly" do
    expect_raises(H2O::TimeoutError) do
      raise H2O::TimeoutError.new("test")
    end
  end
end
