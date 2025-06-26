require "json"

module H2O
  # Public interface for external circuit breaker integration
  module CircuitBreakerAdapter
    abstract def before_request(url : String, headers : Headers) : Bool
    abstract def after_success(response : Response, duration : Time::Span) : Nil
    abstract def after_failure(exception : Exception, duration : Time::Span) : Nil
    abstract def should_allow_request? : Bool
  end

  module CircuitBreaker
    # Public interface for external fiber/channel integration
    module FiberAdapter
      abstract def execute_with_timeout(timeout : Time::Span, &block)
      abstract def handle_spawn_failure(exception : Exception) : Nil
    end

    # Public persistence adapter interface
    abstract class PersistenceAdapter
      abstract def save_state(name : String, state : CircuitBreakerState) : Nil
      abstract def load_state(name : String) : CircuitBreakerState?
      abstract def save_statistics(name : String, stats : Statistics) : Nil
      abstract def load_statistics(name : String) : Statistics?
    end

    alias FailureCallback = Proc(Exception, Statistics, Nil)
    alias StateCallback = Proc(State, State, Nil)

    enum State
      Closed   # Normal operation
      Open     # Failing, reject requests
      HalfOpen # Testing recovery
    end

    class Statistics
      include JSON::Serializable

      property consecutive_failures : Int32 = 0
      property failure_count : Int32 = 0
      property last_failure_time : Time? = nil
      property last_success_time : Time? = nil
      property success_count : Int32 = 0
      property timeout_count : Int32 = 0
      property total_requests : Int32 = 0

      def initialize(@consecutive_failures : Int32 = 0,
                     @failure_count : Int32 = 0,
                     @last_failure_time : Time? = nil,
                     @last_success_time : Time? = nil,
                     @success_count : Int32 = 0,
                     @timeout_count : Int32 = 0,
                     @total_requests : Int32 = 0)
      end

      def record_failure!(current_time : Time, is_timeout : Bool = false) : Nil
        @consecutive_failures += 1
        @failure_count += 1
        @last_failure_time = current_time
        @timeout_count += 1 if is_timeout
        @total_requests += 1
      end

      def record_success!(current_time : Time) : Nil
        @consecutive_failures = 0
        @last_success_time = current_time
        @success_count += 1
        @total_requests += 1
      end

      def reset! : Nil
        @consecutive_failures = 0
        @failure_count = 0
        @last_failure_time = nil
        @last_success_time = nil
        @success_count = 0
        @timeout_count = 0
        @total_requests = 0
      end
    end

    record CircuitBreakerState,
      consecutive_failures : Int32 = 0,
      failure_count : Int32 = 0,
      last_failure_time : Time? = nil,
      last_success_time : Time? = nil,
      state : State = State::Closed,
      success_count : Int32 = 0,
      timeout_count : Int32 = 0,
      total_requests : Int32 = 0 do
      include JSON::Serializable

      def self.from_statistics(stats : Statistics, state : State) : CircuitBreakerState
        new(
          consecutive_failures: stats.consecutive_failures,
          failure_count: stats.failure_count,
          last_failure_time: stats.last_failure_time,
          last_success_time: stats.last_success_time,
          state: state,
          success_count: stats.success_count,
          timeout_count: stats.timeout_count,
          total_requests: stats.total_requests
        )
      end

      def to_statistics : Statistics
        Statistics.new(
          consecutive_failures: @consecutive_failures,
          failure_count: @failure_count,
          last_failure_time: @last_failure_time,
          last_success_time: @last_success_time,
          success_count: @success_count,
          timeout_count: @timeout_count,
          total_requests: @total_requests
        )
      end
    end

    # Default fiber adapter implementation
    class DefaultFiberAdapter
      include FiberAdapter

      def execute_with_timeout(timeout : Time::Span, &block : -> T) forall T
        start_time = Time.monotonic
        result = block.call
        duration = Time.monotonic - start_time

        if duration > timeout
          raise TimeoutError.new("Circuit breaker operation timed out after #{duration}")
        end

        result
      end

      def handle_spawn_failure(exception : Exception) : Nil
        H2O::Log.error { "Fiber spawn failure in circuit breaker: #{exception.message}" }
      end
    end

    # Built-in local file persistence
    class LocalFileAdapter < PersistenceAdapter
      def initialize(@storage_path : String = "./.h2o_circuit_breaker")
        begin
          Dir.mkdir_p(@storage_path) unless Dir.exists?(@storage_path)
        rescue ex : Exception
          H2O::Log.warn { "Failed to create circuit breaker storage directory: #{ex.message}" }
        end
      end

      def load_state(name : String) : CircuitBreakerState?
        path = File.join(@storage_path, "#{name}_state.json")
        return nil unless File.exists?(path)
        CircuitBreakerState.from_json(File.read(path))
      rescue ex : Exception
        H2O::Log.warn { "Failed to load circuit breaker state for #{name}: #{ex.message}" }
        nil
      end

      def load_statistics(name : String) : Statistics?
        path = File.join(@storage_path, "#{name}_stats.json")
        return nil unless File.exists?(path)
        Statistics.from_json(File.read(path))
      rescue ex : Exception
        H2O::Log.warn { "Failed to load circuit breaker statistics for #{name}: #{ex.message}" }
        nil
      end

      def save_state(name : String, state : CircuitBreakerState) : Nil
        path = File.join(@storage_path, "#{name}_state.json")
        File.write(path, state.to_json)
      rescue ex : Exception
        H2O::Log.warn { "Failed to save circuit breaker state for #{name}: #{ex.message}" }
      end

      def save_statistics(name : String, stats : Statistics) : Nil
        path = File.join(@storage_path, "#{name}_stats.json")
        File.write(path, stats.to_json)
      rescue ex : Exception
        H2O::Log.warn { "Failed to save circuit breaker statistics for #{name}: #{ex.message}" }
      end
    end

    # In-memory persistence adapter for testing
    class InMemoryAdapter < PersistenceAdapter
      def initialize
        @states = Hash(String, CircuitBreakerState).new
        @statistics = Hash(String, Statistics).new
      end

      def load_state(name : String) : CircuitBreakerState?
        @states[name]?
      end

      def load_statistics(name : String) : Statistics?
        @statistics[name]?
      end

      def save_state(name : String, state : CircuitBreakerState) : Nil
        @states[name] = state
      end

      def save_statistics(name : String, stats : Statistics) : Nil
        @statistics[name] = stats
      end
    end
  end

  # Main circuit breaker class
  class Breaker
    # Public API for external access
    getter failure_threshold : Int32
    getter name : String
    getter recovery_timeout : Time::Span
    getter state : CircuitBreaker::State
    getter statistics : CircuitBreaker::Statistics
    getter timeout : Time::Span

    def initialize(@name : String,
                   @failure_threshold : Int32 = 5,
                   @recovery_timeout : Time::Span = 60.seconds,
                   @timeout : Time::Span = 30.seconds,
                   @persistence : CircuitBreaker::PersistenceAdapter? = nil,
                   @fiber_adapter : CircuitBreaker::FiberAdapter? = nil)
      @state = CircuitBreaker::State::Closed
      @statistics = CircuitBreaker::Statistics.new
      @mutex = Mutex.new
      @fiber_adapter ||= CircuitBreaker::DefaultFiberAdapter.new
      @failure_callbacks = [] of CircuitBreaker::FailureCallback
      @state_change_callbacks = [] of CircuitBreaker::StateCallback
      load_persisted_state if @persistence
    end

    # Execute a request with circuit breaker protection
    def execute(url : String, headers : Headers, &block : RequestBlock) : CircuitBreakerResult
      unless should_allow_request?
        return Response.error(503, "Circuit breaker open - request blocked", "HTTP/2")
      end

      start_time = Time.monotonic
      begin
        if fiber_adapter = @fiber_adapter
          result = fiber_adapter.execute_with_timeout(@timeout) { block.call }
        else
          result = block.call
        end
        duration = Time.monotonic - start_time
        record_success(duration)
        result
      rescue ex : Exception
        duration = Time.monotonic - start_time
        record_failure(ex, duration)
        handle_failure(ex)
        Response.error(500, "Circuit breaker caught exception: #{ex.message}", "HTTP/2")
      end
    end

    # Public methods for external integration
    def force_half_open : Nil
      @mutex.synchronize do
        old_state = @state
        @state = CircuitBreaker::State::HalfOpen
        persist_state if @persistence
        notify_state_change(old_state, @state)
      end
    end

    def force_open : Nil
      @mutex.synchronize do
        old_state = @state
        @state = CircuitBreaker::State::Open
        # Set a recent failure time to prevent immediate recovery
        @statistics.last_failure_time = Time.utc
        persist_state if @persistence
        notify_state_change(old_state, @state)
      end
    end

    def on_failure(&block : CircuitBreaker::FailureCallback) : Nil
      @failure_callbacks << block
    end

    def on_state_change(&block : CircuitBreaker::StateCallback) : Nil
      @state_change_callbacks << block
    end

    def reset : Nil
      @mutex.synchronize do
        old_state = @state
        @state = CircuitBreaker::State::Closed
        @statistics.reset!
        persist_state if @persistence
        notify_state_change(old_state, @state)
      end
    end

    def should_allow_request? : Bool
      @mutex.synchronize do
        case @state
        when .closed?
          true
        when .open?
          return false unless recovery_period_elapsed?
          transition_to_half_open
          true
        when .half_open?
          true
        else
          false
        end
      end
    end

    # Callback registration for external monitoring
    private def handle_failure(exception : Exception) : Nil
      @failure_callbacks.each(&.call(exception, @statistics))
    end

    private def load_persisted_state : Nil
      if persistence = @persistence
        if persisted_state = persistence.load_state(@name)
          @state = persisted_state.state
          @statistics = persisted_state.to_statistics
        end
      end
    end

    private def notify_state_change(old_state : CircuitBreaker::State, new_state : CircuitBreaker::State) : Nil
      @state_change_callbacks.each(&.call(old_state, new_state))
    end

    private def persist_state : Nil
      if persistence = @persistence
        state_record = CircuitBreaker::CircuitBreakerState.from_statistics(@statistics, @state)
        persistence.save_state(@name, state_record)
        persistence.save_statistics(@name, @statistics)
      end
    end

    private def recovery_period_elapsed? : Bool
      return true unless last_failure = @statistics.last_failure_time
      Time.utc - last_failure >= @recovery_timeout
    end

    private def record_failure(exception : Exception, duration : Time::Span) : Nil
      current_time = Time.utc
      @mutex.synchronize do
        @statistics.record_failure!(current_time, exception.is_a?(TimeoutError))

        if @statistics.consecutive_failures >= @failure_threshold
          transition_to_open
        end

        persist_state if @persistence
      end
    end

    private def record_success(duration : Time::Span) : Nil
      current_time = Time.utc
      @mutex.synchronize do
        old_state = @state
        @statistics.record_success!(current_time)

        if @state.half_open?
          transition_to_closed
        end

        persist_state if @persistence
      end
    end

    private def transition_to_closed : Nil
      old_state = @state
      @state = CircuitBreaker::State::Closed
      notify_state_change(old_state, @state)
    end

    private def transition_to_half_open : Nil
      old_state = @state
      @state = CircuitBreaker::State::HalfOpen
      notify_state_change(old_state, @state)
    end

    private def transition_to_open : Nil
      old_state = @state
      @state = CircuitBreaker::State::Open
      notify_state_change(old_state, @state)
    end
  end
end
