# H2O Circuit Breaker

H2O includes a built-in circuit breaker for handling service failures.

## Quick Start

```crystal
require "h2o"

# Enable globally
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
end

client = H2O::Client.new
response = client.get("https://api.example.com/data")
```

## Per-Client Configuration

```crystal
client = H2O::Client.new(
  circuit_breaker_enabled: true,
  timeout: 10.seconds
)
```

## Custom Circuit Breaker

```crystal
breaker = H2O::CircuitBreaker.new(
  name: "api_breaker",
  failure_threshold: 3,
  recovery_timeout: 30.seconds,
  timeout: 5.seconds
)

client = H2O::Client.new(default_circuit_breaker: breaker)
```

## Persistence

### File-based
```crystal
persistence = H2O::CircuitBreaker::LocalFileAdapter.new(".circuit_breaker_data")
breaker = H2O::CircuitBreaker.new("api", persistence: persistence)
```

### Custom Adapter
```crystal
class MyAdapter
  include H2O::CircuitBreakerAdapter
  
  def should_allow_request? : Bool
    @external_breaker.closed?
  end
  
  def before_request(url : String, headers : H2O::Headers) : Bool
    true
  end
  
  def after_success(response : H2O::Response, duration : Time::Span) : Nil
  end
  
  def after_failure(exception : Exception, duration : Time::Span) : Nil
  end
end

client = H2O::Client.new(circuit_breaker_adapter: MyAdapter.new)
```

## Monitoring

```crystal
breaker.on_state_change do |old_state, new_state|
  puts "State: #{old_state} -> #{new_state}"
end

breaker.on_failure do |exception, statistics|
  puts "Failure: #{exception.message}"
end

# Access state
puts breaker.state                    # :closed, :open, :half_open
puts breaker.statistics.success_count
puts breaker.statistics.failure_count
```

## States

- **Closed**: Normal operation, requests pass through
- **Open**: Failing, requests rejected immediately  
- **Half-Open**: Testing recovery, limited requests allowed

Circuit opens when failure threshold is reached. After recovery timeout, it transitions to half-open to test if service has recovered.