require "../spec_helper"

describe H2O::Breaker do
  describe "#initialize" do
    it "creates a circuit breaker with default values" do
      breaker = H2O::Breaker.new("test")
      breaker.name.should eq("test")
      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)
      breaker.failure_threshold.should eq(5)
      breaker.recovery_timeout.should eq(60.seconds)
      breaker.timeout.should eq(30.seconds)
    end

    it "creates a circuit breaker with custom values" do
      breaker = H2O::Breaker.new(
        "custom",
        failure_threshold: 3,
        recovery_timeout: 30.seconds,
        timeout: 10.seconds
      )
      breaker.name.should eq("custom")
      breaker.failure_threshold.should eq(3)
      breaker.recovery_timeout.should eq(30.seconds)
      breaker.timeout.should eq(10.seconds)
    end
  end

  describe "#should_allow_request?" do
    it "allows requests when circuit is closed" do
      breaker = H2O::Breaker.new("test")
      breaker.should_allow_request?.should be_true
    end

    it "blocks requests when circuit is open" do
      breaker = H2O::Breaker.new("test")
      breaker.force_open
      breaker.should_allow_request?.should be_false
    end

    it "allows requests when circuit is half-open" do
      breaker = H2O::Breaker.new("test")
      breaker.force_half_open
      breaker.should_allow_request?.should be_true
    end
  end

  describe "#execute" do
    it "executes block successfully and records success" do
      breaker = H2O::Breaker.new("test")
      response = H2O::Response.new(200)

      result = breaker.execute("http://example.com", H2O::Headers.new) { response }

      result.should eq(response)
      breaker.statistics.success_count.should eq(1)
      breaker.statistics.consecutive_failures.should eq(0)
    end

    it "handles exceptions and records failures" do
      breaker = H2O::Breaker.new("test", failure_threshold: 2)

      result = breaker.execute("http://example.com", H2O::Headers.new) do
        raise Exception.new("Test error")
      end

      result.should be_nil
      breaker.statistics.failure_count.should eq(1)
      breaker.statistics.consecutive_failures.should eq(1)
    end

    it "transitions to open state after threshold failures" do
      breaker = H2O::Breaker.new("test", failure_threshold: 2)

      # First failure
      breaker.execute("http://example.com", H2O::Headers.new) do
        raise Exception.new("Test error")
      end
      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)

      # Second failure - should open circuit
      breaker.execute("http://example.com", H2O::Headers.new) do
        raise Exception.new("Test error")
      end
      breaker.state.should eq(H2O::CircuitBreaker::State::Open)
    end

    it "returns nil when circuit is open" do
      breaker = H2O::Breaker.new("test")
      breaker.force_open

      result = breaker.execute("http://example.com", H2O::Headers.new) do
        H2O::Response.new(200)
      end

      result.should be_nil
    end
  end

  describe "#reset" do
    it "resets circuit breaker to closed state" do
      breaker = H2O::Breaker.new("test")
      breaker.force_open

      breaker.reset

      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)
      breaker.statistics.failure_count.should eq(0)
      breaker.statistics.success_count.should eq(0)
    end
  end

  describe "state callbacks" do
    it "calls state change callbacks" do
      breaker = H2O::Breaker.new("test")
      old_state = nil
      new_state = nil

      breaker.on_state_change do |old, new|
        old_state = old
        new_state = new
      end

      breaker.force_open

      old_state.should eq(H2O::CircuitBreaker::State::Closed)
      new_state.should eq(H2O::CircuitBreaker::State::Open)
    end

    it "calls failure callbacks" do
      breaker = H2O::Breaker.new("test")
      callback_exception = nil
      callback_stats = nil

      breaker.on_failure do |ex, stats|
        callback_exception = ex
        callback_stats = stats
      end

      breaker.execute("http://example.com", H2O::Headers.new) do
        raise Exception.new("Test error")
      end

      callback_exception.should_not be_nil
      if ex = callback_exception
        ex.message.should eq("Test error")
      end
      callback_stats.should_not be_nil
    end
  end
end

describe H2O::CircuitBreaker::Statistics do
  describe "#from_json and #to_json" do
    it "serializes and deserializes correctly" do
      original = H2O::CircuitBreaker::Statistics.new(
        consecutive_failures: 3,
        failure_count: 10,
        success_count: 5,
        total_requests: 15
      )

      json = original.to_json
      restored = H2O::CircuitBreaker::Statistics.from_json(json)

      restored.consecutive_failures.should eq(3)
      restored.failure_count.should eq(10)
      restored.success_count.should eq(5)
      restored.total_requests.should eq(15)
    end
  end
end

describe H2O::CircuitBreaker::InMemoryAdapter do
  describe "persistence operations" do
    it "saves and loads state correctly" do
      adapter = H2O::CircuitBreaker::InMemoryAdapter.new
      state = H2O::CircuitBreaker::CircuitBreakerState.new(
        state: H2O::CircuitBreaker::State::Open,
        failure_count: 5
      )

      adapter.save_state("test", state)
      loaded_state = adapter.load_state("test")

      loaded_state.should_not be_nil
      if state = loaded_state
        state.state.should eq(H2O::CircuitBreaker::State::Open)
        state.failure_count.should eq(5)
      end
    end

    it "saves and loads statistics correctly" do
      adapter = H2O::CircuitBreaker::InMemoryAdapter.new
      stats = H2O::CircuitBreaker::Statistics.new(
        success_count: 10,
        failure_count: 3
      )

      adapter.save_statistics("test", stats)
      loaded_stats = adapter.load_statistics("test")

      loaded_stats.should_not be_nil
      if stats = loaded_stats
        stats.success_count.should eq(10)
        stats.failure_count.should eq(3)
      end
    end

    it "returns nil for non-existent entries" do
      adapter = H2O::CircuitBreaker::InMemoryAdapter.new

      adapter.load_state("nonexistent").should be_nil
      adapter.load_statistics("nonexistent").should be_nil
    end
  end
end

describe H2O::CircuitBreaker::LocalFileAdapter do
  describe "file persistence operations" do
    it "saves and loads state from files" do
      temp_dir = "/tmp/h2o_test_#{Random.rand(1000)}"
      adapter = H2O::CircuitBreaker::LocalFileAdapter.new(temp_dir)

      state = H2O::CircuitBreaker::CircuitBreakerState.new(
        state: H2O::CircuitBreaker::State::HalfOpen,
        consecutive_failures: 2
      )

      adapter.save_state("file_test", state)
      loaded_state = adapter.load_state("file_test")

      loaded_state.should_not be_nil
      if state = loaded_state
        state.state.should eq(H2O::CircuitBreaker::State::HalfOpen)
        state.consecutive_failures.should eq(2)
      end

      # Cleanup
      File.delete(File.join(temp_dir, "file_test_state.json")) if File.exists?(File.join(temp_dir, "file_test_state.json"))
      Dir.delete(temp_dir) if Dir.exists?(temp_dir)
    end

    it "handles file errors gracefully" do
      adapter = H2O::CircuitBreaker::LocalFileAdapter.new("/invalid/path")

      # Should not raise exception, just log warning
      adapter.load_state("test").should be_nil
    end
  end
end

describe H2O::CircuitBreaker::DefaultFiberAdapter do
  describe "#execute_with_timeout" do
    it "executes block within timeout" do
      adapter = H2O::CircuitBreaker::DefaultFiberAdapter.new

      result = adapter.execute_with_timeout(1.seconds) do
        "success"
      end

      result.should eq("success")
    end

    it "raises timeout error when block takes too long" do
      adapter = H2O::CircuitBreaker::DefaultFiberAdapter.new

      expect_raises(H2O::TimeoutError, /timed out/) do
        adapter.execute_with_timeout(0.1.seconds) do
          sleep(0.2.seconds)
          "never reached"
        end
      end
    end

    it "propagates exceptions from block" do
      adapter = H2O::CircuitBreaker::DefaultFiberAdapter.new

      expect_raises(Exception, "test exception") do
        adapter.execute_with_timeout(1.seconds) do
          raise Exception.new("test exception")
        end
      end
    end
  end
end
