# H2O Integration Guide

## Installation

```yaml
# shard.yml
dependencies:
  h2o:
    github: nomadlabsinc/h2o
    branch: main
```

```bash
shards install
```

## Basic Setup

```crystal
require "h2o"

# Global configuration (recommended)
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
end

client = H2O::Client.new
response = client.get("https://api.example.com/data")
```

## Production Configuration

### Database Persistence
```crystal
# Custom database adapter
class DatabasePersistence
  include H2O::CircuitBreakerAdapter
  
  def initialize(@db : DB::Database)
  end
  
  def should_allow_request? : Bool
    # Check database for breaker state
    result = @db.query_one("SELECT state FROM circuit_breakers WHERE name = ?", @name)
    result != "open"
  end
  
  # Implement other required methods...
end

persistence = DatabasePersistence.new(database)
breaker = H2O::CircuitBreaker.new("api_service", persistence: persistence)
client = H2O::Client.new(default_circuit_breaker: breaker)
```

### Service-Specific Configuration
```crystal
# Different settings per service
payment_breaker = H2O::CircuitBreaker.new(
  name: "payment_service",
  failure_threshold: 2,
  recovery_timeout: 120.seconds
)

user_breaker = H2O::CircuitBreaker.new(
  name: "user_service", 
  failure_threshold: 5,
  recovery_timeout: 30.seconds
)

payment_client = H2O::Client.new(default_circuit_breaker: payment_breaker)
user_client = H2O::Client.new(default_circuit_breaker: user_breaker)
```

## Monitoring

```crystal
breaker.on_state_change do |old_state, new_state|
  Log.warn { "Circuit breaker #{breaker.name}: #{old_state} -> #{new_state}" }
  # Send to monitoring system
end

breaker.on_failure do |exception, stats|
  Log.error { "Circuit breaker failure: #{exception.message}" }
  # Increment failure metrics
end
```

## Migration from External Circuit Breakers

```crystal
# Wrap existing circuit breaker
class ExistingBreakerAdapter
  include H2O::CircuitBreakerAdapter
  
  def initialize(@existing_breaker)
  end
  
  def should_allow_request? : Bool
    @existing_breaker.allow_request?
  end
  
  def before_request(url : String, headers : H2O::Headers) : Bool
    @existing_breaker.record_attempt
    true
  end
  
  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    @existing_breaker.record_success
  end
  
  def after_failure(exception : Exception, duration : Time::Span) : Nil
    @existing_breaker.record_failure
  end
end

adapter = ExistingBreakerAdapter.new(your_existing_breaker)
client = H2O::Client.new(circuit_breaker_adapter: adapter)
```

## Connection Pooling

```crystal
# Configure connection pool
client = H2O::Client.new(
  connection_pool_size: 20,
  timeout: 10.seconds
)

# Pool automatically reuses connections for same host
response1 = client.get("https://api.example.com/users")
response2 = client.get("https://api.example.com/posts")  # Reuses connection
```

## Error Handling

```crystal
begin
  response = client.get("https://api.example.com/data")
  if response
    puts response.body
  else
    puts "Request failed"
  end
rescue H2O::CircuitBreakerOpenError
  puts "Circuit breaker is open"
rescue H2O::TimeoutError
  puts "Request timed out"
rescue H2O::ConnectionError
  puts "Connection failed"
end
```

## Testing

```crystal
# Use in-memory adapter for tests
test_adapter = H2O::CircuitBreaker::InMemoryAdapter.new
test_breaker = H2O::CircuitBreaker.new("test", persistence: test_adapter)
client = H2O::Client.new(default_circuit_breaker: test_breaker)

# Disable circuit breaker for specific tests
response = client.get(url, bypass_circuit_breaker: true)
```