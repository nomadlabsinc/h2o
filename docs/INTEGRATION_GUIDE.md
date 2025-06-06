# H2O Circuit Breaker Integration Guide

This guide provides comprehensive instructions for integrating the H2O HTTP/2 client with its built-in circuit breaker functionality, including persistence store setup and configuration examples.

## Table of Contents

- [Quick Start](#quick-start)
- [Basic Configuration](#basic-configuration)
- [Persistence Store Setup](#persistence-store-setup)
- [Advanced Configuration](#advanced-configuration)
- [Migration from External Circuit Breakers](#migration-from-external-circuit-breakers)
- [Monitoring and Observability](#monitoring-and-observability)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Quick Start

### 1. Add H2O to Your Project

Add to your `shard.yml`:

```yaml
dependencies:
  h2o:
    github: nomadlabsinc/h2o
    version: "~> 1.0"
```

### 2. Basic Setup with Circuit Breaker Enabled

```crystal
require "h2o"

# Enable circuit breaker globally (recommended)
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
  config.default_timeout = 30.seconds
end

# Create client and make requests
client = H2O::Client.new
response = client.get("https://api.example.com/data")

if response
  puts "Success: #{response.status}"
  puts response.body
else
  puts "Request failed or circuit breaker is open"
end
```

## Basic Configuration

### Global Configuration (Recommended)

Configure circuit breaker settings globally for all H2O clients:

```crystal
H2O.configure do |config|
  # Enable circuit breaker by default
  config.circuit_breaker_enabled = true
  
  # Failure threshold before opening circuit
  config.default_failure_threshold = 5
  
  # Time to wait before attempting recovery
  config.default_recovery_timeout = 60.seconds
  
  # Request timeout
  config.default_timeout = 30.seconds
end
```

### Per-Client Configuration

Override global settings for specific clients:

```crystal
# Client with custom circuit breaker settings
client = H2O::Client.new(
  circuit_breaker_enabled: true,
  timeout: 10.seconds
)

# Client with circuit breaker disabled
fallback_client = H2O::Client.new(
  circuit_breaker_enabled: false
)
```

### Per-Request Control

Fine-tune circuit breaker behavior per request:

```crystal
client = H2O::Client.new

# Enable circuit breaker for specific request
response = client.get("https://api.example.com/data", circuit_breaker: true)

# Bypass circuit breaker for health checks
health_response = client.get("https://api.example.com/health", bypass_circuit_breaker: true)

# Use default client configuration
normal_response = client.get("https://api.example.com/users")
```

## Persistence Store Setup

### Database-Based Persistence (PostgreSQL Example)

Create a custom persistence adapter that integrates with your existing database:

```crystal
require "pg"
require "h2o"

class DatabaseCircuitBreakerPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@db : DB::Database)
    ensure_table_exists
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @db.query_one?(
      "SELECT state, consecutive_failures, failure_count, last_failure_time, 
              success_count, timeout_count, total_requests 
       FROM circuit_breaker_states WHERE name = $1",
      name
    ) do |rs|
      H2O::CircuitBreaker::CircuitBreakerState.new(
        consecutive_failures: rs.read(Int32),
        failure_count: rs.read(Int32),
        last_failure_time: rs.read(Time?),
        last_success_time: rs.read(Time?),
        state: H2O::CircuitBreaker::State.parse(rs.read(String)),
        success_count: rs.read(Int32),
        timeout_count: rs.read(Int32),
        total_requests: rs.read(Int32)
      )
    end
  rescue ex : Exception
    Log.error { "Failed to load circuit breaker state for #{name}: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    @db.exec(
      "INSERT INTO circuit_breaker_states 
       (name, state, consecutive_failures, failure_count, last_failure_time, 
        last_success_time, success_count, timeout_count, total_requests, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (name) DO UPDATE SET
         state = EXCLUDED.state,
         consecutive_failures = EXCLUDED.consecutive_failures,
         failure_count = EXCLUDED.failure_count,
         last_failure_time = EXCLUDED.last_failure_time,
         last_success_time = EXCLUDED.last_success_time,
         success_count = EXCLUDED.success_count,
         timeout_count = EXCLUDED.timeout_count,
         total_requests = EXCLUDED.total_requests,
         updated_at = EXCLUDED.updated_at",
      name, state.state.to_s, state.consecutive_failures, state.failure_count,
      state.last_failure_time, state.last_success_time, state.success_count,
      state.timeout_count, state.total_requests, Time.utc
    )
  rescue ex : Exception
    Log.error { "Failed to save circuit breaker state for #{name}: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    # Can return nil if state loading covers statistics
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    # Can be empty if state saving covers statistics
  end

  private def ensure_table_exists : Nil
    @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS circuit_breaker_states (
        name VARCHAR(255) PRIMARY KEY,
        state VARCHAR(20) NOT NULL,
        consecutive_failures INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure_time TIMESTAMP,
        last_success_time TIMESTAMP,
        success_count INTEGER NOT NULL DEFAULT 0,
        timeout_count INTEGER NOT NULL DEFAULT 0,
        total_requests INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    SQL
  end
end
```

### Setting Up the Database Persistence

```crystal
# Database connection
db = DB.open("postgres://user:password@localhost/myapp_production")

# Create persistence adapter
persistence = DatabaseCircuitBreakerPersistence.new(db)

# Create circuit breaker with persistence
api_breaker = H2O::Breaker.new(
  name: "api_service",
  failure_threshold: 3,
  recovery_timeout: 30.seconds,
  persistence: persistence
)

# Use with H2O client
client = H2O::Client.new(
  circuit_breaker_enabled: true,
  default_circuit_breaker: api_breaker
)
```

### File-Based Persistence (Development/Testing)

For development or smaller deployments, use local file persistence:

```crystal
# Local file persistence
file_persistence = H2O::CircuitBreaker::LocalFileAdapter.new("./circuit_breaker_data")

breaker = H2O::Breaker.new(
  name: "dev_api",
  persistence: file_persistence
)

client = H2O::Client.new(default_circuit_breaker: breaker)
```

### Redis-Based Persistence

For distributed applications, implement Redis persistence:

```crystal
require "redis"

class RedisCircuitBreakerPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@redis : Redis)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    data = @redis.get("circuit_breaker:#{name}")
    return nil unless data
    
    H2O::CircuitBreaker::CircuitBreakerState.from_json(data)
  rescue ex : Exception
    Log.error { "Failed to load circuit breaker state from Redis: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    @redis.setex("circuit_breaker:#{name}", 86400, state.to_json)
  rescue ex : Exception
    Log.error { "Failed to save circuit breaker state to Redis: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil # Covered by state loading
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    # Covered by state saving
  end
end

# Usage
redis = Redis.new(host: "localhost", port: 6379)
persistence = RedisCircuitBreakerPersistence.new(redis)

breaker = H2O::Breaker.new(
  name: "distributed_api",
  persistence: persistence
)
```

## Advanced Configuration

### Custom Circuit Breaker Adapter

Integrate with existing circuit breaker infrastructure:

```crystal
class ExistingCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  def initialize(@external_breaker : MyExistingCircuitBreaker)
  end

  def before_request(url : String, headers : H2O::Headers) : Bool
    @external_breaker.should_allow_request?(url)
  end

  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    @external_breaker.record_success(response.status, duration.total_milliseconds)
  end

  def after_failure(exception : Exception, duration : Time::Span) : Nil
    @external_breaker.record_failure(exception.class.name, duration.total_milliseconds)
  end

  def should_allow_request? : Bool
    @external_breaker.state.closed?
  end
end

# Usage
adapter = ExistingCircuitBreakerAdapter.new(my_existing_breaker)
client = H2O::Client.new(circuit_breaker_adapter: adapter)
```

### Multiple Service Configuration

Configure different circuit breakers for different services:

```crystal
# API service circuit breaker
api_persistence = DatabaseCircuitBreakerPersistence.new(db)
api_breaker = H2O::Breaker.new(
  name: "api_service",
  failure_threshold: 5,
  recovery_timeout: 60.seconds,
  persistence: api_persistence
)

# Payment service circuit breaker (more sensitive)
payment_persistence = DatabaseCircuitBreakerPersistence.new(db)
payment_breaker = H2O::Breaker.new(
  name: "payment_service",
  failure_threshold: 2,
  recovery_timeout: 120.seconds,
  persistence: payment_persistence
)

# Create specialized clients
api_client = H2O::Client.new(default_circuit_breaker: api_breaker)
payment_client = H2O::Client.new(default_circuit_breaker: payment_breaker)

# Use clients for different services
user_data = api_client.get("https://api.example.com/users/#{user_id}")
payment_result = payment_client.post("https://payments.example.com/charge", payment_data)
```

## Migration from External Circuit Breakers

### Step 1: Assess Current Implementation

Before migrating, document your current circuit breaker:
- Failure thresholds
- Recovery timeouts
- Persistence mechanism
- Monitoring/alerting integration

### Step 2: Create Migration Strategy

```crystal
# Phase 1: Parallel operation for testing
class MigrationCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  def initialize(@old_breaker : OldCircuitBreaker, @new_breaker : H2O::Breaker)
    @comparison_enabled = ENV["CIRCUIT_BREAKER_COMPARISON"] == "true"
  end

  def before_request(url : String, headers : H2O::Headers) : Bool
    old_decision = @old_breaker.should_allow_request?(url)
    new_decision = @new_breaker.should_allow_request?

    if @comparison_enabled && old_decision != new_decision
      Log.warn { "Circuit breaker decision mismatch: old=#{old_decision}, new=#{new_decision}" }
    end

    # Use old breaker decision during migration
    old_decision
  end

  # ... implement other methods similarly
end
```

### Step 3: Gradual Rollout

```crystal
# Use feature flags for gradual migration
def create_circuit_breaker_client(service_name : String) : H2O::Client
  if ENV["USE_H2O_CIRCUIT_BREAKER"] == "true"
    # New H2O circuit breaker
    persistence = DatabaseCircuitBreakerPersistence.new(db)
    breaker = H2O::Breaker.new(
      name: service_name,
      failure_threshold: get_threshold_for_service(service_name),
      recovery_timeout: get_timeout_for_service(service_name),
      persistence: persistence
    )
    
    H2O::Client.new(default_circuit_breaker: breaker)
  else
    # Existing circuit breaker with adapter
    adapter = ExistingCircuitBreakerAdapter.new(existing_breakers[service_name])
    H2O::Client.new(circuit_breaker_adapter: adapter)
  end
end
```

## Monitoring and Observability

### State Change Monitoring

```crystal
# Set up circuit breaker monitoring
breaker = H2O::Breaker.new("monitored_service")

# Monitor state changes
breaker.on_state_change do |old_state, new_state|
  case new_state
  when .open?
    alert_service.send_alert(
      "Circuit breaker OPENED for monitored_service",
      severity: "critical",
      tags: ["circuit_breaker", "service_down"]
    )
  when .closed?
    alert_service.send_alert(
      "Circuit breaker CLOSED for monitored_service",
      severity: "info", 
      tags: ["circuit_breaker", "service_recovered"]
    )
  when .half_open?
    Log.info { "Circuit breaker testing recovery for monitored_service" }
  end
end

# Monitor failures
breaker.on_failure do |exception, statistics|
  metrics_service.increment("circuit_breaker.failures", {
    service: "monitored_service",
    exception_type: exception.class.name
  })
  
  if statistics.consecutive_failures >= (breaker.failure_threshold * 0.8).to_i
    Log.warn { "Circuit breaker approaching threshold: #{statistics.consecutive_failures}/#{breaker.failure_threshold}" }
  end
end
```

### Metrics Collection

```crystal
# Custom metrics collection
class MetricsCircuitBreakerMonitor
  def initialize(@breaker : H2O::Breaker, @metrics : MetricsClient)
    setup_monitoring
  end

  private def setup_monitoring : Nil
    @breaker.on_state_change do |old_state, new_state|
      @metrics.gauge("circuit_breaker.state", state_to_number(new_state), {
        service: @breaker.name,
        previous_state: old_state.to_s
      })
    end

    # Report statistics periodically
    spawn do
      loop do
        sleep 30.seconds
        report_statistics
      end
    end
  end

  private def report_statistics : Nil
    stats = @breaker.statistics
    tags = {service: @breaker.name}

    @metrics.gauge("circuit_breaker.success_count", stats.success_count, tags)
    @metrics.gauge("circuit_breaker.failure_count", stats.failure_count, tags)
    @metrics.gauge("circuit_breaker.consecutive_failures", stats.consecutive_failures, tags)
    @metrics.gauge("circuit_breaker.total_requests", stats.total_requests, tags)
  end

  private def state_to_number(state : H2O::CircuitBreaker::State) : Int32
    case state
    when .closed? then 0
    when .half_open? then 1
    when .open? then 2
    else 3
    end
  end
end

# Usage
monitor = MetricsCircuitBreakerMonitor.new(breaker, metrics_client)
```

## Best Practices

### 1. Configuration Management

```crystal
# Use environment-based configuration
class CircuitBreakerConfig
  def self.for_service(service_name : String) : H2O::Breaker
    H2O::Breaker.new(
      name: service_name,
      failure_threshold: ENV["#{service_name.upcase}_FAILURE_THRESHOLD"]?.try(&.to_i) || 5,
      recovery_timeout: ENV["#{service_name.upcase}_RECOVERY_TIMEOUT"]?.try(&.to_i.seconds) || 60.seconds,
      timeout: ENV["#{service_name.upcase}_TIMEOUT"]?.try(&.to_i.seconds) || 30.seconds,
      persistence: create_persistence_for_service(service_name)
    )
  end

  private def self.create_persistence_for_service(service_name : String)
    case ENV["CIRCUIT_BREAKER_PERSISTENCE"]?
    when "database"
      DatabaseCircuitBreakerPersistence.new(Database.connection)
    when "redis"
      RedisCircuitBreakerPersistence.new(Redis.connection)
    else
      H2O::CircuitBreaker::LocalFileAdapter.new("./circuit_breaker_#{service_name}")
    end
  end
end
```

### 2. Health Check Integration

```crystal
# Integrate with health check endpoints
class HealthCheckService
  def initialize(@clients : Hash(String, H2O::Client))
  end

  def health_status : Hash(String, String)
    @clients.transform_values do |client|
      # Always bypass circuit breaker for health checks
      response = client.get("/health", bypass_circuit_breaker: true)
      response && response.status == 200 ? "healthy" : "unhealthy"
    end
  end

  def circuit_breaker_status : Hash(String, String)
    @clients.transform_values do |client|
      if breaker = client.default_circuit_breaker
        breaker.state.to_s
      else
        "disabled"
      end
    end
  end
end
```

### 3. Graceful Degradation

```crystal
# Implement fallback strategies
def fetch_user_data(user_id : String) : UserData?
  primary_response = primary_api_client.get("/users/#{user_id}")
  
  if primary_response && primary_response.status == 200
    UserData.from_json(primary_response.body)
  else
    # Fallback to cache or secondary service
    fetch_user_from_cache(user_id) || fetch_user_from_backup_service(user_id)
  end
end

def fetch_user_from_backup_service(user_id : String) : UserData?
  # Backup service with different circuit breaker settings
  backup_response = backup_api_client.get("/users/#{user_id}")
  
  if backup_response && backup_response.status == 200
    UserData.from_json(backup_response.body)
  else
    nil
  end
end
```

## Troubleshooting

### Common Issues

#### 1. Circuit Breaker Not Opening

**Symptoms:** Service continues to fail but circuit breaker remains closed.

**Solutions:**
```crystal
# Check failure threshold configuration
breaker = H2O::Breaker.new(
  name: "debug_service",
  failure_threshold: 3, # Lower threshold for testing
  recovery_timeout: 10.seconds # Shorter timeout for testing
)

# Add debug logging
breaker.on_failure do |exception, statistics|
  Log.debug { "Failure #{statistics.consecutive_failures}/#{breaker.failure_threshold}: #{exception.message}" }
end
```

#### 2. Circuit Breaker Not Recovering

**Symptoms:** Circuit breaker remains open indefinitely.

**Solutions:**
```crystal
# Check recovery timeout
breaker.on_state_change do |old_state, new_state|
  Log.info { "State change: #{old_state} -> #{new_state}" }
  
  if new_state.half_open?
    Log.info { "Testing recovery - next request will determine state" }
  end
end

# Manual recovery for testing
breaker.force_half_open
```

#### 3. Persistence Issues

**Symptoms:** Circuit breaker state not persisting across restarts.

**Solutions:**
```crystal
# Test persistence adapter
persistence = DatabaseCircuitBreakerPersistence.new(db)

# Save test state
test_state = H2O::CircuitBreaker::CircuitBreakerState.new(
  state: H2O::CircuitBreaker::State::Open,
  failure_count: 5
)
persistence.save_state("test", test_state)

# Load and verify
loaded_state = persistence.load_state("test")
puts "Loaded state: #{loaded_state.inspect}"
```

### Debug Mode

Enable debug logging for detailed circuit breaker behavior:

```crystal
# Enable debug logging
Log.setup("h2o", :debug)

# Or configure specific circuit breaker logging
H2O::Log.level = Log::Severity::Debug

# Add custom debug adapter
class DebugCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  def initialize(@name : String)
  end

  def before_request(url : String, headers : H2O::Headers) : Bool
    Log.debug { "[#{@name}] Before request to #{url}" }
    true
  end

  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    Log.debug { "[#{@name}] Success: #{response.status} in #{duration.total_milliseconds}ms" }
  end

  def after_failure(exception : Exception, duration : Time::Span) : Nil
    Log.debug { "[#{@name}] Failure: #{exception.class.name} in #{duration.total_milliseconds}ms" }
  end

  def should_allow_request? : Bool
    Log.debug { "[#{@name}] Allowing request" }
    true
  end
end
```

## Support

For additional help:
- Check the [API Documentation](./API_REFERENCE.md)
- Review the [Examples](./examples/)
- Open an issue on [GitHub](https://github.com/nomadlabsinc/h2o/issues)

---

This integration guide provides everything you need to successfully implement H2O's circuit breaker functionality in your Crystal application. Start with the basic configuration and gradually add persistence and monitoring as your needs grow.
