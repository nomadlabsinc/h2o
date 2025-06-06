# H2O API Reference

Complete API reference for the H2O HTTP/2 client library with circuit breaker functionality.

## Table of Contents

- [Global Configuration](#global-configuration)
- [H2O::Client](#h2oclient)
- [H2O::Breaker](#h2obreaker)
- [Circuit Breaker Adapters](#circuit-breaker-adapters)
- [Persistence Adapters](#persistence-adapters)
- [Types and Enums](#types-and-enums)
- [Exceptions](#exceptions)

## Global Configuration

### H2O.configure

Configure global H2O settings.

```crystal
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
  config.default_timeout = 30.seconds
end
```

#### Configuration Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `circuit_breaker_enabled` | `Bool` | `false` | Enable circuit breaker globally |
| `default_failure_threshold` | `Int32` | `5` | Default failure threshold for circuit breakers |
| `default_recovery_timeout` | `Time::Span` | `60.seconds` | Default recovery timeout |
| `default_timeout` | `Time::Span` | `30.seconds` | Default request timeout |

### H2O.config

Access current global configuration.

```crystal
config = H2O.config
puts config.circuit_breaker_enabled
```

## H2O::Client

Main HTTP/2 client class with circuit breaker integration.

### Constructor

```crystal
def initialize(connection_pool_size : Int32 = 10,
               timeout : Time::Span = H2O.config.default_timeout,
               circuit_breaker_enabled : Bool = H2O.config.circuit_breaker_enabled,
               circuit_breaker_adapter : CircuitBreakerAdapter? = nil,
               default_circuit_breaker : Breaker? = H2O.config.default_circuit_breaker)
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `connection_pool_size` | `Int32` | `10` | Maximum number of concurrent connections |
| `timeout` | `Time::Span` | Global config | Request timeout |
| `circuit_breaker_enabled` | `Bool` | Global config | Enable circuit breaker for this client |
| `circuit_breaker_adapter` | `CircuitBreakerAdapter?` | `nil` | Custom circuit breaker adapter |
| `default_circuit_breaker` | `Breaker?` | Global config | Default circuit breaker instance |

### HTTP Methods

All HTTP methods support circuit breaker control through named parameters.

#### GET Request

```crystal
def get(url : String, 
        headers : Headers = Headers.new, 
        *, 
        bypass_circuit_breaker : Bool = false, 
        circuit_breaker : Bool? = nil) : Response?
```

#### POST Request

```crystal
def post(url : String, 
         body : String? = nil, 
         headers : Headers = Headers.new, 
         *, 
         bypass_circuit_breaker : Bool = false, 
         circuit_breaker : Bool? = nil) : Response?
```

#### PUT Request

```crystal
def put(url : String, 
        body : String? = nil, 
        headers : Headers = Headers.new, 
        *, 
        bypass_circuit_breaker : Bool = false, 
        circuit_breaker : Bool? = nil) : Response?
```

#### DELETE Request

```crystal
def delete(url : String, 
           headers : Headers = Headers.new, 
           *, 
           bypass_circuit_breaker : Bool = false, 
           circuit_breaker : Bool? = nil) : Response?
```

#### HEAD Request

```crystal
def head(url : String, 
         headers : Headers = Headers.new, 
         *, 
         bypass_circuit_breaker : Bool = false, 
         circuit_breaker : Bool? = nil) : Response?
```

#### OPTIONS Request

```crystal
def options(url : String, 
            headers : Headers = Headers.new, 
            *, 
            bypass_circuit_breaker : Bool = false, 
            circuit_breaker : Bool? = nil) : Response?
```

#### PATCH Request

```crystal
def patch(url : String, 
          body : String? = nil, 
          headers : Headers = Headers.new, 
          *, 
          bypass_circuit_breaker : Bool = false, 
          circuit_breaker : Bool? = nil) : Response?
```

#### Circuit Breaker Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bypass_circuit_breaker` | `Bool` | `false` | Skip circuit breaker for this request |
| `circuit_breaker` | `Bool?` | `nil` | Override client circuit breaker setting |

### Generic Request Method

```crystal
def request(method : String, 
            url : String, 
            headers : Headers = Headers.new, 
            body : String? = nil, 
            *, 
            bypass_circuit_breaker : Bool = false, 
            circuit_breaker : Bool? = nil) : Response?
```

### Connection Management

#### Close Connections

```crystal
def close : Nil
```

Closes all active connections and clears the connection pool.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `circuit_breaker_adapter` | `CircuitBreakerAdapter?` | Custom circuit breaker adapter |
| `circuit_breaker_enabled` | `Bool` | Circuit breaker enabled state |
| `connection_pool_size` | `Int32` | Maximum connection pool size |
| `connections` | `ConnectionsHash` | Active connections |
| `default_circuit_breaker` | `Breaker?` | Default circuit breaker instance |
| `timeout` | `Time::Span` | Request timeout |

## H2O::Breaker

Circuit breaker implementation.

### Constructor

```crystal
def initialize(name : String,
               failure_threshold : Int32 = 5,
               recovery_timeout : Time::Span = 60.seconds,
               timeout : Time::Span = 30.seconds,
               persistence : CircuitBreaker::PersistenceAdapter? = nil,
               fiber_adapter : CircuitBreaker::FiberAdapter? = nil)
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `String` | Required | Unique circuit breaker name |
| `failure_threshold` | `Int32` | `5` | Failures before opening circuit |
| `recovery_timeout` | `Time::Span` | `60.seconds` | Time to wait before recovery attempt |
| `timeout` | `Time::Span` | `30.seconds` | Request timeout |
| `persistence` | `PersistenceAdapter?` | `nil` | State persistence adapter |
| `fiber_adapter` | `FiberAdapter?` | `nil` | Custom fiber handling adapter |

### State Management

#### Check Request Permission

```crystal
def should_allow_request? : Bool
```

Returns `true` if the circuit breaker allows the request.

#### Force State Changes

```crystal
def force_open : Nil
def force_half_open : Nil
def reset : Nil
```

- `force_open`: Manually open the circuit breaker
- `force_half_open`: Force into half-open state for testing
- `reset`: Reset to closed state with cleared statistics

### Request Execution

```crystal
def execute(url : RequestUrl, headers : Headers, &block : RequestBlock) : CircuitBreakerResult
```

Execute a request block with circuit breaker protection.

### Event Callbacks

#### State Change Callback

```crystal
def on_state_change(&block : CircuitBreaker::StateCallback) : Nil
```

Register callback for state changes.

```crystal
breaker.on_state_change do |old_state, new_state|
  puts "State changed: #{old_state} -> #{new_state}"
end
```

#### Failure Callback

```crystal
def on_failure(&block : CircuitBreaker::FailureCallback) : Nil
```

Register callback for failures.

```crystal
breaker.on_failure do |exception, statistics|
  puts "Failure: #{exception.message}"
  puts "Stats: #{statistics.inspect}"
end
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `failure_threshold` | `Int32` | Failure threshold |
| `name` | `String` | Circuit breaker name |
| `recovery_timeout` | `Time::Span` | Recovery timeout |
| `state` | `CircuitBreaker::State` | Current state |
| `statistics` | `CircuitBreaker::Statistics` | Current statistics |
| `timeout` | `Time::Span` | Request timeout |

## Circuit Breaker Adapters

### CircuitBreakerAdapter Module

Interface for integrating external circuit breaker logic.

```crystal
module CircuitBreakerAdapter
  abstract def before_request(url : String, headers : Headers) : Bool
  abstract def after_success(response : Response, duration : Time::Span) : Nil
  abstract def after_failure(exception : Exception, duration : Time::Span) : Nil
  abstract def should_allow_request? : Bool
end
```

#### Method Descriptions

| Method | Description |
|--------|-------------|
| `before_request` | Called before each request, return `false` to block |
| `after_success` | Called after successful requests |
| `after_failure` | Called after failed requests |
| `should_allow_request?` | Check if requests should be allowed |

### FiberAdapter Module

Interface for custom fiber/channel integration.

```crystal
module FiberAdapter
  abstract def execute_with_timeout(timeout : Time::Span, &block)
  abstract def handle_spawn_failure(exception : Exception) : Nil
end
```

#### Method Descriptions

| Method | Description |
|--------|-------------|
| `execute_with_timeout` | Execute block with timeout handling |
| `handle_spawn_failure` | Handle fiber spawn failures |

## Persistence Adapters

### PersistenceAdapter Abstract Class

Base class for state persistence implementations.

```crystal
abstract class PersistenceAdapter
  abstract def save_state(name : String, state : CircuitBreakerState) : Nil
  abstract def load_state(name : String) : CircuitBreakerState?
  abstract def save_statistics(name : String, stats : Statistics) : Nil
  abstract def load_statistics(name : String) : Statistics?
end
```

#### Method Descriptions

| Method | Description |
|--------|-------------|
| `save_state` | Persist circuit breaker state |
| `load_state` | Load circuit breaker state |
| `save_statistics` | Persist statistics |
| `load_statistics` | Load statistics |

### Built-in Adapters

#### LocalFileAdapter

```crystal
class LocalFileAdapter < PersistenceAdapter
  def initialize(storage_path : String = "./.h2o_circuit_breaker")
end
```

Stores state in local JSON files.

#### InMemoryAdapter

```crystal
class InMemoryAdapter < PersistenceAdapter
  def initialize
end
```

Stores state in memory (testing only).

## Types and Enums

### State Enum

```crystal
enum State
  Closed   # Normal operation
  Open     # Failing, reject requests
  HalfOpen # Testing recovery
end
```

### Statistics Class

```crystal
class Statistics
  property consecutive_failures : Int32 = 0
  property failure_count : Int32 = 0
  property last_failure_time : Time? = nil
  property last_success_time : Time? = nil
  property success_count : Int32 = 0
  property timeout_count : Int32 = 0
  property total_requests : Int32 = 0
  
  def record_failure!(current_time : Time, is_timeout : Bool = false) : Nil
  def record_success!(current_time : Time) : Nil
  def reset! : Nil
end
```

### CircuitBreakerState Record

```crystal
record CircuitBreakerState,
  consecutive_failures : Int32 = 0,
  failure_count : Int32 = 0,
  last_failure_time : Time? = nil,
  last_success_time : Time? = nil,
  state : State = State::Closed,
  success_count : Int32 = 0,
  timeout_count : Int32 = 0,
  total_requests : Int32 = 0
```

### Type Aliases

```crystal
# Circuit breaker related aliases
alias CircuitBreakerResult = Response?
alias ConnectionResult = BaseConnection?
alias ProtocolResult = ProtocolVersion?
alias RequestBlock = Proc(Response?)
alias RequestUrl = String
alias UrlParseResult = {URI, String}

# Client method parameter aliases
alias CircuitBreakerOptions = NamedTuple(
  bypass_circuit_breaker: Bool,
  circuit_breaker: Bool?
)

# Connection management aliases
alias ConnectionKey = String
alias HostPort = {String, Int32}

# Callback type aliases
alias FailureCallback = Proc(Exception, Statistics, Nil)
alias StateCallback = Proc(State, State, Nil)
```

### Response Class

```crystal
class Response
  property status : Int32
  property headers : Headers
  property body : String
  property protocol : String

  def initialize(status : Int32, 
                 headers : Headers = Headers.new, 
                 body : String = "", 
                 protocol : String = "HTTP/2")
end
```

## Exceptions

### H2O-Specific Exceptions

#### TimeoutError

```crystal
class TimeoutError < Exception
end
```

Raised when requests exceed timeout limits.

#### CircuitBreakerOpenError

```crystal
class CircuitBreakerOpenError < Exception
end
```

Raised when circuit breaker is open and blocking requests.

### Standard Exceptions

H2O may also raise standard Crystal exceptions:

- `ArgumentError` - Invalid arguments (e.g., malformed URLs)
- `IO::TimeoutError` - Network timeouts
- `Socket::Error` - Network connection errors
- `OpenSSL::SSL::Error` - TLS/SSL errors

## Usage Examples

### Basic Client Usage

```crystal
require "h2o"

# Global configuration
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
end

# Create client
client = H2O::Client.new

# Make requests
response = client.get("https://api.example.com/users")
if response
  puts "Status: #{response.status}"
  puts "Body: #{response.body}"
end
```

### Custom Circuit Breaker

```crystal
# Create custom circuit breaker
breaker = H2O::Breaker.new(
  name: "api_service",
  failure_threshold: 3,
  recovery_timeout: 30.seconds
)

# Add monitoring
breaker.on_state_change do |old_state, new_state|
  puts "Circuit breaker state: #{old_state} -> #{new_state}"
end

# Create client with custom breaker
client = H2O::Client.new(default_circuit_breaker: breaker)
```

### External Adapter Integration

```crystal
class MyCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  def should_allow_request? : Bool
    # Your logic here
    true
  end

  def before_request(url : String, headers : H2O::Headers) : Bool
    # Your pre-request logic
    true
  end

  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    # Your success tracking
  end

  def after_failure(exception : Exception, duration : Time::Span) : Nil
    # Your failure tracking
  end
end

adapter = MyCircuitBreakerAdapter.new
client = H2O::Client.new(circuit_breaker_adapter: adapter)
```

### Persistence Integration

```crystal
require "pg"

class DatabasePersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@db : DB::Database)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    # Load from database
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    # Save to database
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end
end

# Usage
db = DB.open("postgres://...")
persistence = DatabasePersistence.new(db)
breaker = H2O::Breaker.new("api_service", persistence: persistence)
client = H2O::Client.new(default_circuit_breaker: breaker)
```

---

This API reference provides complete documentation for all public interfaces in the H2O library. For more examples and integration patterns, see the [Integration Guide](./INTEGRATION_GUIDE.md) and [Configuration Examples](./CONFIGURATION_EXAMPLES.md).
