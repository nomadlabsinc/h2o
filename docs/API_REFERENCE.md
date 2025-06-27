# H2O API Reference

## H2O::Client

### Constructor
```crystal
H2O::Client.new(
  connection_pool_size: Int32 = 10,
  timeout: Time::Span = 30.seconds,
  circuit_breaker_enabled: Bool = false,
  default_circuit_breaker: CircuitBreaker? = nil,
  circuit_breaker_adapter: CircuitBreakerAdapter? = nil
)
```

### HTTP Methods
```crystal
client.get(url : String, headers : Headers? = nil) : Response?
client.post(url : String, body : String? = nil, headers : Headers? = nil) : Response?
client.put(url : String, body : String? = nil, headers : Headers? = nil) : Response?
client.delete(url : String, headers : Headers? = nil) : Response?
client.head(url : String, headers : Headers? = nil) : Response?
client.options(url : String, headers : Headers? = nil) : Response?
client.patch(url : String, body : String? = nil, headers : Headers? = nil) : Response?
```

### Per-Request Options
```crystal
client.get(url, headers, circuit_breaker: true)
client.get(url, headers, bypass_circuit_breaker: true)
```

## H2O::CircuitBreaker

### Constructor
```crystal
H2O::CircuitBreaker.new(
  name: String,
  failure_threshold: Int32 = 5,
  recovery_timeout: Time::Span = 60.seconds,
  timeout: Time::Span = 30.seconds,
  persistence: PersistenceAdapter? = nil
)
```

### State Management
```crystal
breaker.state : Symbol                    # :closed, :open, :half_open
breaker.statistics : Statistics
breaker.reset                            # Reset to closed state
```

### Callbacks
```crystal
breaker.on_state_change(&block : Symbol, Symbol ->)
breaker.on_failure(&block : Exception, Statistics ->)
```

## H2O::Response

```crystal
response.status : Int32
response.body : String
response.headers : Headers
```

## H2O::Headers

```crystal
headers = H2O::Headers.new
headers["content-type"] = "application/json"
headers["authorization"] = "Bearer token"
```

## Global Configuration

```crystal
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
  config.default_timeout = 30.seconds
end
```

## Persistence Adapters

### Local File
```crystal
H2O::CircuitBreaker::LocalFileAdapter.new(file_path : String)
```

### In-Memory (testing)
```crystal
H2O::CircuitBreaker::InMemoryAdapter.new
```

### Custom Adapter Interface
```crystal
module H2O::CircuitBreakerAdapter
  abstract def should_allow_request? : Bool
  abstract def before_request(url : String, headers : Headers) : Bool
  abstract def after_success(response : Response, duration : Time::Span) : Nil
  abstract def after_failure(exception : Exception, duration : Time::Span) : Nil
end
```

## Statistics

```crystal
statistics.success_count : Int64
statistics.failure_count : Int64
statistics.total_requests : Int64
statistics.last_failure_time : Time?
statistics.last_success_time : Time?
```

## Exceptions

- `H2O::CircuitBreakerOpenError` - Circuit breaker is open
- `H2O::TimeoutError` - Request timeout
- `H2O::ConnectionError` - Connection failed
- `H2O::ProtocolError` - HTTP/2 protocol error