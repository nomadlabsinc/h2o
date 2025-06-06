# H2O Configuration Examples

This document provides real-world configuration examples for the H2O HTTP/2 client with circuit breaker functionality enabled by default.

## Table of Contents

- [Basic Configurations](#basic-configurations)
- [Production Configurations](#production-configurations)
- [Service-Specific Configurations](#service-specific-configurations)
- [Persistence Configurations](#persistence-configurations)
- [Monitoring Configurations](#monitoring-configurations)
- [Environment-Specific Configurations](#environment-specific-configurations)

## Basic Configurations

### Default Production Setup

```crystal
require "h2o"

# Recommended production configuration with circuit breaker enabled
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
  config.default_timeout = 30.seconds
end

# Simple client usage
client = H2O::Client.new
response = client.get("https://api.example.com/data")
```

### Development Configuration

```crystal
# Development setup with shorter timeouts for faster feedback
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 3
  config.default_recovery_timeout = 10.seconds
  config.default_timeout = 5.seconds
end

# Local file persistence for development
persistence = H2O::CircuitBreaker::LocalFileAdapter.new("./dev_circuit_breaker")
breaker = H2O::Breaker.new("dev_api", persistence: persistence)

client = H2O::Client.new(default_circuit_breaker: breaker)
```

### Testing Configuration

```crystal
# Test configuration with in-memory persistence
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 2
  config.default_recovery_timeout = 1.seconds
  config.default_timeout = 1.seconds
end

# In-memory persistence for tests
test_persistence = H2O::CircuitBreaker::InMemoryAdapter.new
test_breaker = H2O::Breaker.new("test_api", persistence: test_persistence)

client = H2O::Client.new(default_circuit_breaker: test_breaker)
```

## Production Configurations

### High-Availability Service

```crystal
require "pg"

# Database persistence setup
class ProductionPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@db : DB::Database)
    ensure_schema
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @db.query_one?(
      "SELECT state, consecutive_failures, failure_count, last_failure_time, 
              last_success_time, success_count, timeout_count, total_requests 
       FROM circuit_breaker_states WHERE service_name = $1",
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
  rescue ex
    Log.error { "Failed to load circuit breaker state: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    @db.exec(
      "INSERT INTO circuit_breaker_states 
       (service_name, state, consecutive_failures, failure_count, last_failure_time,
        last_success_time, success_count, timeout_count, total_requests, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
       ON CONFLICT (service_name) DO UPDATE SET
         state = EXCLUDED.state,
         consecutive_failures = EXCLUDED.consecutive_failures,
         failure_count = EXCLUDED.failure_count,
         last_failure_time = EXCLUDED.last_failure_time,
         last_success_time = EXCLUDED.last_success_time,
         success_count = EXCLUDED.success_count,
         timeout_count = EXCLUDED.timeout_count,
         total_requests = EXCLUDED.total_requests,
         updated_at = NOW()",
      name, state.state.to_s, state.consecutive_failures, state.failure_count,
      state.last_failure_time, state.last_success_time, state.success_count,
      state.timeout_count, state.total_requests
    )
  rescue ex
    Log.error { "Failed to save circuit breaker state: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil # Statistics included in state
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    # Statistics saved with state
  end

  private def ensure_schema : Nil
    @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS circuit_breaker_states (
        id SERIAL PRIMARY KEY,
        service_name VARCHAR(255) UNIQUE NOT NULL,
        state VARCHAR(20) NOT NULL,
        consecutive_failures INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure_time TIMESTAMP NULL,
        last_success_time TIMESTAMP NULL,
        success_count INTEGER NOT NULL DEFAULT 0,
        timeout_count INTEGER NOT NULL DEFAULT 0,
        total_requests INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
      
      CREATE INDEX IF NOT EXISTS idx_circuit_breaker_service_name 
      ON circuit_breaker_states(service_name);
    SQL
  end
end

# Production configuration
DB_URL = ENV["DATABASE_URL"]
db = DB.open(DB_URL)
persistence = ProductionPersistence.new(db)

H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
  config.default_timeout = 30.seconds
end

# Main API circuit breaker
main_api_breaker = H2O::Breaker.new(
  name: "main_api",
  failure_threshold: 5,
  recovery_timeout: 60.seconds,
  persistence: persistence
)

# Critical service circuit breaker (more conservative)
payment_breaker = H2O::Breaker.new(
  name: "payment_service",
  failure_threshold: 2,
  recovery_timeout: 120.seconds,
  persistence: persistence
)

# Clients
main_client = H2O::Client.new(default_circuit_breaker: main_api_breaker)
payment_client = H2O::Client.new(default_circuit_breaker: payment_breaker)
```

### Microservices Architecture

```crystal
class ServiceClients
  SERVICES = {
    "user_service" => {
      url: ENV["USER_SERVICE_URL"],
      failure_threshold: 3,
      recovery_timeout: 30.seconds,
      timeout: 10.seconds
    },
    "order_service" => {
      url: ENV["ORDER_SERVICE_URL"],
      failure_threshold: 5,
      recovery_timeout: 60.seconds,
      timeout: 15.seconds
    },
    "inventory_service" => {
      url: ENV["INVENTORY_SERVICE_URL"],
      failure_threshold: 4,
      recovery_timeout: 45.seconds,
      timeout: 20.seconds
    },
    "notification_service" => {
      url: ENV["NOTIFICATION_SERVICE_URL"],
      failure_threshold: 10, # More tolerant for non-critical service
      recovery_timeout: 30.seconds,
      timeout: 5.seconds
    }
  }

  def self.setup_clients : Hash(String, H2O::Client)
    persistence = ProductionPersistence.new(Database.connection)
    
    SERVICES.transform_values do |config|
      breaker = H2O::Breaker.new(
        name: service_name,
        failure_threshold: config[:failure_threshold],
        recovery_timeout: config[:recovery_timeout],
        timeout: config[:timeout],
        persistence: persistence
      )
      
      # Add monitoring
      breaker.on_state_change do |old_state, new_state|
        Metrics.gauge("circuit_breaker.state_change", 1, {
          service: service_name,
          from: old_state.to_s,
          to: new_state.to_s
        })
        
        if new_state.open?
          Alerting.send_alert(
            "Circuit breaker opened for #{service_name}",
            severity: "critical"
          )
        end
      end
      
      H2O::Client.new(
        default_circuit_breaker: breaker,
        timeout: config[:timeout]
      )
    end
  end
end

# Usage
clients = ServiceClients.setup_clients

# Make requests
user_response = clients["user_service"].get("/users/#{user_id}")
order_response = clients["order_service"].post("/orders", order_data)
```

## Service-Specific Configurations

### Payment Service (High Reliability)

```crystal
# Payment service requires highest reliability
payment_persistence = ProductionPersistence.new(Database.connection)

payment_breaker = H2O::Breaker.new(
  name: "payment_processor",
  failure_threshold: 1, # Very conservative
  recovery_timeout: 300.seconds, # 5 minutes
  timeout: 60.seconds # Longer timeout for payment processing
)

# Add extensive monitoring for payments
payment_breaker.on_failure do |exception, statistics|
  # Immediate alert for payment failures
  PagerDuty.trigger_incident(
    "Payment circuit breaker failure",
    details: {
      exception: exception.class.name,
      message: exception.message,
      consecutive_failures: statistics.consecutive_failures,
      total_failures: statistics.failure_count
    }
  )
end

payment_client = H2O::Client.new(
  default_circuit_breaker: payment_breaker,
  timeout: 60.seconds
)
```

### Analytics Service (Fault Tolerant)

```crystal
# Analytics can tolerate more failures
analytics_breaker = H2O::Breaker.new(
  name: "analytics_service",
  failure_threshold: 20, # Very tolerant
  recovery_timeout: 30.seconds, # Quick recovery
  timeout: 5.seconds # Fast timeout
)

# Non-critical monitoring
analytics_breaker.on_state_change do |old_state, new_state|
  if new_state.open?
    Log.warn { "Analytics service circuit breaker opened - analytics temporarily disabled" }
  elsif new_state.closed?
    Log.info { "Analytics service recovered" }
  end
end

analytics_client = H2O::Client.new(
  default_circuit_breaker: analytics_breaker,
  timeout: 5.seconds
)

# Graceful degradation for analytics
def track_event(event_data : Hash)
  response = analytics_client.post("/events", event_data.to_json)
  
  unless response && response.status == 200
    # Fall back to local logging
    Log.info { "Event tracked locally: #{event_data}" }
  end
rescue ex
  # Never fail the main application for analytics
  Log.warn { "Analytics tracking failed: #{ex.message}" }
end
```

### External API Integration

```crystal
# Third-party API with rate limiting considerations
external_api_breaker = H2O::Breaker.new(
  name: "external_weather_api",
  failure_threshold: 3,
  recovery_timeout: 120.seconds, # Respect rate limits
  timeout: 10.seconds
)

# Add rate limit aware recovery
external_api_breaker.on_failure do |exception, statistics|
  if exception.message.includes?("rate limit")
    # Extend recovery time for rate limit errors
    external_api_breaker.force_open
    spawn do
      sleep 300.seconds # Wait 5 minutes for rate limit reset
      external_api_breaker.force_half_open
    end
  end
end

external_client = H2O::Client.new(
  default_circuit_breaker: external_api_breaker
)
```

## Persistence Configurations

### Redis Cluster Configuration

```crystal
require "redis"

class RedisClusterPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@redis_nodes : Array(Redis))
    @hash_ring = ConsistentHashRing.new(@redis_nodes)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    redis = @hash_ring.get_node(name)
    data = redis.get("cb:state:#{name}")
    return nil unless data
    
    H2O::CircuitBreaker::CircuitBreakerState.from_json(data)
  rescue ex
    Log.error { "Redis cluster load error: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    redis = @hash_ring.get_node(name)
    redis.setex("cb:state:#{name}", 86400, state.to_json)
  rescue ex
    Log.error { "Redis cluster save error: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end
end

# Setup Redis cluster
redis_nodes = [
  Redis.new(host: "redis1.example.com"),
  Redis.new(host: "redis2.example.com"),
  Redis.new(host: "redis3.example.com")
]

cluster_persistence = RedisClusterPersistence.new(redis_nodes)
```

### Multi-Backend Persistence

```crystal
class MultiBeckendPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@primary : H2O::CircuitBreaker::PersistenceAdapter, 
                 @fallback : H2O::CircuitBreaker::PersistenceAdapter)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @primary.load_state(name) || @fallback.load_state(name)
  rescue ex
    Log.warn { "Primary persistence failed, trying fallback: #{ex.message}" }
    @fallback.load_state(name)
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    # Save to both backends
    spawn { @primary.save_state(name, state) }
    spawn { @fallback.save_state(name, state) }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end
end

# Usage
primary = ProductionPersistence.new(Database.connection)
fallback = H2O::CircuitBreaker::LocalFileAdapter.new("./backup_circuit_breaker")
multi_persistence = MultiBeckendPersistence.new(primary, fallback)
```

## Monitoring Configurations

### Comprehensive Monitoring Setup

```crystal
class CircuitBreakerMonitoring
  def initialize(@metrics : MetricsClient, @alerting : AlertingClient)
  end

  def setup_monitoring(breaker : H2O::Breaker) : Nil
    # State change monitoring
    breaker.on_state_change do |old_state, new_state|
      @metrics.gauge("circuit_breaker.state", state_to_number(new_state), {
        service: breaker.name,
        previous_state: old_state.to_s
      })

      case new_state
      when .open?
        @alerting.send_alert(
          "Circuit breaker OPENED: #{breaker.name}",
          severity: determine_severity(breaker.name),
          tags: ["circuit_breaker", "service_down", breaker.name]
        )
      when .closed?
        @alerting.send_alert(
          "Circuit breaker RECOVERED: #{breaker.name}",
          severity: "info",
          tags: ["circuit_breaker", "service_recovered", breaker.name]
        )
      end
    end

    # Failure monitoring
    breaker.on_failure do |exception, statistics|
      @metrics.increment("circuit_breaker.failures", {
        service: breaker.name,
        exception_type: exception.class.name
      })

      # Warning when approaching threshold
      if statistics.consecutive_failures >= (breaker.failure_threshold * 0.8).to_i
        @alerting.send_alert(
          "Circuit breaker approaching threshold: #{breaker.name}",
          severity: "warning",
          details: {
            consecutive_failures: statistics.consecutive_failures,
            threshold: breaker.failure_threshold,
            percentage: (statistics.consecutive_failures.to_f / breaker.failure_threshold * 100).round(1)
          }
        )
      end
    end

    # Periodic statistics reporting
    spawn do
      loop do
        sleep 60.seconds
        report_statistics(breaker)
      end
    end
  end

  private def report_statistics(breaker : H2O::Breaker) : Nil
    stats = breaker.statistics
    tags = {service: breaker.name}

    @metrics.gauge("circuit_breaker.success_rate", calculate_success_rate(stats), tags)
    @metrics.gauge("circuit_breaker.total_requests", stats.total_requests, tags)
    @metrics.gauge("circuit_breaker.consecutive_failures", stats.consecutive_failures, tags)
  end

  private def calculate_success_rate(stats : H2O::CircuitBreaker::Statistics) : Float64
    return 100.0 if stats.total_requests == 0
    (stats.success_count.to_f / stats.total_requests * 100).round(2)
  end

  private def state_to_number(state : H2O::CircuitBreaker::State) : Int32
    case state
    when .closed? then 0
    when .half_open? then 1
    when .open? then 2
    else 3
    end
  end

  private def determine_severity(service_name : String) : String
    case service_name
    when .includes?("payment"), .includes?("critical")
      "critical"
    when .includes?("user"), .includes?("order")
      "high"
    when .includes?("analytics"), .includes?("logging")
      "low"
    else
      "medium"
    end
  end
end

# Setup monitoring
monitoring = CircuitBreakerMonitoring.new(metrics_client, alerting_client)

# Apply to all circuit breakers
[main_api_breaker, payment_breaker, analytics_breaker].each do |breaker|
  monitoring.setup_monitoring(breaker)
end
```

## Environment-Specific Configurations

### Environment Configuration Factory

```crystal
class CircuitBreakerConfig
  def self.create_for_environment(environment : String) : H2O::Client
    case environment
    when "production"
      create_production_client
    when "staging"
      create_staging_client
    when "development"
      create_development_client
    when "test"
      create_test_client
    else
      raise ArgumentError.new("Unknown environment: #{environment}")
    end
  end

  private def self.create_production_client : H2O::Client
    # Production persistence
    db = DB.open(ENV["DATABASE_URL"])
    persistence = ProductionPersistence.new(db)

    # Production circuit breaker
    breaker = H2O::Breaker.new(
      name: "production_api",
      failure_threshold: 5,
      recovery_timeout: 60.seconds,
      timeout: 30.seconds,
      persistence: persistence
    )

    # Production monitoring
    setup_production_monitoring(breaker)

    H2O::Client.new(
      circuit_breaker_enabled: true,
      default_circuit_breaker: breaker,
      timeout: 30.seconds
    )
  end

  private def self.create_staging_client : H2O::Client
    # Staging uses database but with relaxed settings
    db = DB.open(ENV["STAGING_DATABASE_URL"])
    persistence = ProductionPersistence.new(db)

    breaker = H2O::Breaker.new(
      name: "staging_api",
      failure_threshold: 3,
      recovery_timeout: 30.seconds,
      timeout: 15.seconds,
      persistence: persistence
    )

    H2O::Client.new(
      circuit_breaker_enabled: true,
      default_circuit_breaker: breaker,
      timeout: 15.seconds
    )
  end

  private def self.create_development_client : H2O::Client
    # Development uses local file persistence
    persistence = H2O::CircuitBreaker::LocalFileAdapter.new("./dev_circuit_breaker")

    breaker = H2O::Breaker.new(
      name: "dev_api",
      failure_threshold: 2,
      recovery_timeout: 5.seconds,
      timeout: 5.seconds,
      persistence: persistence
    )

    H2O::Client.new(
      circuit_breaker_enabled: true,
      default_circuit_breaker: breaker,
      timeout: 5.seconds
    )
  end

  private def self.create_test_client : H2O::Client
    # Test uses in-memory persistence
    persistence = H2O::CircuitBreaker::InMemoryAdapter.new

    breaker = H2O::Breaker.new(
      name: "test_api",
      failure_threshold: 1,
      recovery_timeout: 1.seconds,
      timeout: 1.seconds,
      persistence: persistence
    )

    H2O::Client.new(
      circuit_breaker_enabled: true,
      default_circuit_breaker: breaker,
      timeout: 1.seconds
    )
  end

  private def self.setup_production_monitoring(breaker : H2O::Breaker) : Nil
    # Add comprehensive production monitoring
    monitoring = CircuitBreakerMonitoring.new(
      MetricsClient.new(ENV["METRICS_URL"]),
      AlertingClient.new(ENV["ALERTING_URL"])
    )
    monitoring.setup_monitoring(breaker)
  end
end

# Usage based on environment
environment = ENV["CRYSTAL_ENV"]? || "development"
client = CircuitBreakerConfig.create_for_environment(environment)
```

### Docker Environment Configuration

```yaml
# docker-compose.yml
version: '3.8'
services:
  app:
    environment:
      - CIRCUIT_BREAKER_ENABLED=true
      - CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
      - CIRCUIT_BREAKER_RECOVERY_TIMEOUT=60
      - CIRCUIT_BREAKER_TIMEOUT=30
      - CIRCUIT_BREAKER_PERSISTENCE=database
      - DATABASE_URL=postgres://user:pass@postgres:5432/myapp
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:13
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass

  redis:
    image: redis:6-alpine
```

```crystal
# Environment-based configuration
def configure_from_environment : H2O::Client
  H2O.configure do |config|
    config.circuit_breaker_enabled = ENV["CIRCUIT_BREAKER_ENABLED"]? == "true"
    config.default_failure_threshold = ENV["CIRCUIT_BREAKER_FAILURE_THRESHOLD"]?.try(&.to_i) || 5
    config.default_recovery_timeout = ENV["CIRCUIT_BREAKER_RECOVERY_TIMEOUT"]?.try(&.to_i.seconds) || 60.seconds
    config.default_timeout = ENV["CIRCUIT_BREAKER_TIMEOUT"]?.try(&.to_i.seconds) || 30.seconds
  end

  persistence = case ENV["CIRCUIT_BREAKER_PERSISTENCE"]?
                when "database"
                  ProductionPersistence.new(DB.open(ENV["DATABASE_URL"]))
                when "redis"
                  RedisCircuitBreakerPersistence.new(Redis.new(url: ENV["REDIS_URL"]))
                when "file"
                  H2O::CircuitBreaker::LocalFileAdapter.new(ENV["CIRCUIT_BREAKER_FILE_PATH"]? || "./circuit_breaker")
                else
                  H2O::CircuitBreaker::InMemoryAdapter.new
                end

  breaker = H2O::Breaker.new(
    name: ENV["SERVICE_NAME"]? || "default_service",
    persistence: persistence
  )

  H2O::Client.new(default_circuit_breaker: breaker)
end
```

---

These configuration examples demonstrate the flexibility and power of H2O's circuit breaker functionality. Choose the appropriate configuration based on your application's requirements, environment, and reliability needs.
