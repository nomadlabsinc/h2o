require "../spec_helper"

# Test circuit breaker adapter implementation
class TestCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  property allow_requests : Bool = true
  property before_request_called : Bool = false
  property after_success_called : Bool = false
  property after_failure_called : Bool = false
  property last_response : H2O::Response?
  property last_exception : Exception?

  def before_request(url : String, headers : H2O::Headers) : Bool
    @before_request_called = true
    true
  end

  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    @after_success_called = true
    @last_response = response
  end

  def after_failure(exception : Exception, duration : Time::Span) : Nil
    @after_failure_called = true
    @last_exception = exception
  end

  def should_allow_request? : Bool
    @allow_requests
  end
end

# Test fiber adapter implementation
class TestFiberAdapter
  include H2O::CircuitBreaker::FiberAdapter

  property execute_called : Bool = false
  property handle_failure_called : Bool = false
  property last_timeout : Time::Span?

  def execute_with_timeout(timeout : Time::Span, &block : -> T) : T forall T
    @execute_called = true
    @last_timeout = timeout
    block.call
  end

  def handle_spawn_failure(exception : Exception) : Nil
    @handle_failure_called = true
  end
end

describe "Circuit Breaker Integration" do
  describe "H2O::Client with circuit breaker" do
    it "integrates circuit breaker with client requests" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
        config.default_failure_threshold = 2
        config.default_recovery_timeout = 1.seconds
      end

      client = H2O::Client.new(timeout: 1.seconds)

      # This will fail since we don't have a real server
      response = client.get("https://nonexistent.example.com/test")
      response.should be_nil
    end

    it "respects bypass_circuit_breaker flag" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
      end

      client = H2O::Client.new(timeout: 1.seconds)

      # Should bypass circuit breaker
      response = client.get("https://nonexistent.example.com/test", bypass_circuit_breaker: true)
      response.should be_nil
    end

    it "respects circuit_breaker parameter override" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = false
      end

      client = H2O::Client.new(timeout: 1.seconds)

      # Should enable circuit breaker for this request
      response = client.get("https://nonexistent.example.com/test", circuit_breaker: true)
      response.should be_nil
    end
  end

  describe "External circuit breaker adapter integration" do
    it "calls adapter methods correctly" do
      adapter = TestCircuitBreakerAdapter.new
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
      end

      client = H2O::Client.new(
        circuit_breaker_adapter: adapter,
        timeout: 1.seconds
      )

      # This will fail since we don't have a real server
      response = client.get("https://nonexistent.example.com/test")

      adapter.before_request_called.should be_true
      response.should be_nil
    end

    it "blocks requests when adapter disallows them" do
      adapter = TestCircuitBreakerAdapter.new
      adapter.allow_requests = false

      H2O.configure do |config|
        config.circuit_breaker_enabled = true
      end

      client = H2O::Client.new(
        circuit_breaker_adapter: adapter,
        timeout: 1.seconds
      )

      response = client.get("https://httpbin.org/get")
      response.should be_nil
    end
  end

  describe "Fiber compatibility" do
    it "works correctly with spawned fibers" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
        config.default_failure_threshold = 2
      end

      client = H2O::Client.new(timeout: 1.seconds)
      channel = Channel(H2O::Response?).new

      # This demonstrates the fix for the original issue where
      # h2o operations failed in spawned fibers
      spawn do
        response = client.get("https://nonexistent.example.com/test")
        channel.send(response)
      end

      result = channel.receive
      result.should be_nil
    end

    it "handles timeout correctly in fibers" do
      fiber_adapter = TestFiberAdapter.new
      breaker = H2O::Breaker.new(
        "test",
        timeout: 0.1.seconds,
        fiber_adapter: fiber_adapter
      )

      result = breaker.execute("http://example.com", H2O::Headers.new) do
        H2O::Response.new(200)
      end

      fiber_adapter.execute_called.should be_true
      fiber_adapter.last_timeout.should eq(0.1.seconds)
      result.should_not be_nil
    end

    it "propagates exceptions through fiber adapter" do
      fiber_adapter = TestFiberAdapter.new
      breaker = H2O::Breaker.new(
        "test",
        fiber_adapter: fiber_adapter
      )

      result = breaker.execute("http://example.com", H2O::Headers.new) do
        raise Exception.new("Test error")
      end

      result.should be_nil
      breaker.statistics.failure_count.should eq(1)
    end
  end

  describe "Persistence integration" do
    it "persists state across circuit breaker instances" do
      adapter = H2O::CircuitBreaker::InMemoryAdapter.new

      # Create first breaker and trigger some failures
      breaker1 = H2O::Breaker.new(
        "persistent_test",
        failure_threshold: 2,
        persistence: adapter
      )

      # Trigger failures to open circuit
      2.times do
        breaker1.execute("http://example.com", H2O::Headers.new) do
          raise Exception.new("Test error")
        end
      end

      breaker1.state.should eq(H2O::CircuitBreaker::State::Open)

      # Create second breaker with same name and persistence
      breaker2 = H2O::Breaker.new(
        "persistent_test",
        failure_threshold: 2,
        persistence: adapter
      )

      # Should load the open state
      breaker2.state.should eq(H2O::CircuitBreaker::State::Open)
      breaker2.statistics.failure_count.should eq(2)
    end

    it "handles missing persistence gracefully" do
      adapter = H2O::CircuitBreaker::InMemoryAdapter.new

      breaker = H2O::Breaker.new(
        "missing_test",
        persistence: adapter
      )

      # Should start with default closed state
      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)
      breaker.statistics.failure_count.should eq(0)
    end
  end

  describe "Configuration integration" do
    it "uses global configuration defaults" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
        config.default_failure_threshold = 3
        config.default_recovery_timeout = 30.seconds
        config.default_timeout = 5.seconds
      end

      client = H2O::Client.new

      client.circuit_breaker_enabled.should be_true
      client.timeout.should eq(5.seconds)
    end

    it "allows per-client overrides" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
        config.default_timeout = 30.seconds
      end

      client = H2O::Client.new(
        circuit_breaker_enabled: false,
        timeout: 10.seconds
      )

      client.circuit_breaker_enabled.should be_false
      client.timeout.should eq(10.seconds)
    end

    it "allows global circuit breaker configuration" do
      global_breaker = H2O::Breaker.new(
        "global_test",
        failure_threshold: 10
      )

      H2O.configure do |config|
        config.default_circuit_breaker = global_breaker
      end

      client = H2O::Client.new
      client.default_circuit_breaker.should eq(global_breaker)
    end
  end

  describe "Real world scenarios" do
    it "handles multiple concurrent requests with circuit breaker" do
      H2O.configure do |config|
        config.circuit_breaker_enabled = true
        config.default_failure_threshold = 3
      end

      client = H2O::Client.new(timeout: 1.seconds)
      channel = Channel(H2O::Response?).new
      request_count = 5

      # Spawn multiple concurrent requests
      request_count.times do
        spawn do
          response = client.get("https://nonexistent.example.com/test")
          channel.send(response)
        end
      end

      # Collect all responses
      responses = [] of H2O::Response?
      request_count.times do
        responses << channel.receive
      end

      # All should be nil due to connection failures
      responses.all?(Nil).should be_true
    end

    it "demonstrates circuit breaker state transitions" do
      breaker = H2O::Breaker.new(
        "state_test",
        failure_threshold: 2,
        recovery_timeout: 0.1.seconds
      )

      state_changes = [] of {H2O::CircuitBreaker::State, H2O::CircuitBreaker::State}
      breaker.on_state_change do |old_state, new_state|
        state_changes << {old_state, new_state}
      end

      # Start with closed state
      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)

      # Trigger failures to open circuit
      2.times do
        breaker.execute("http://example.com", H2O::Headers.new) do
          raise Exception.new("Test error")
        end
      end

      breaker.state.should eq(H2O::CircuitBreaker::State::Open)
      state_changes.size.should eq(1)
      state_changes[0].should eq({H2O::CircuitBreaker::State::Closed, H2O::CircuitBreaker::State::Open})

      # Wait for recovery timeout
      sleep(0.2.seconds)

      # Next request should transition to half-open
      breaker.execute("http://example.com", H2O::Headers.new) do
        H2O::Response.new(200)
      end

      breaker.state.should eq(H2O::CircuitBreaker::State::Closed)
      state_changes.size.should eq(3) # Open -> HalfOpen -> Closed
    end
  end
end
