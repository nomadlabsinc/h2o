# H2O Documentation

Welcome to the H2O HTTP/2 client documentation. H2O is a high-performance HTTP/2 client for Crystal with built-in circuit breaker functionality.

## 📚 Documentation Index

### Getting Started
- **[Integration Guide](./INTEGRATION_GUIDE.md)** - Comprehensive guide for integrating H2O with circuit breaker functionality
- **[Configuration Examples](./CONFIGURATION_EXAMPLES.md)** - Real-world configuration examples for various scenarios
- **[API Reference](./API_REFERENCE.md)** - Complete API documentation

### Advanced Topics
- **[Persistence Setup](./PERSISTENCE_SETUP.md)** - Database, Redis, and file-based persistence configuration
- **[Migration Guide](./MIGRATION_GUIDE.md)** - Migrating from external circuit breaker solutions
- **[Performance Tuning](./PERFORMANCE_TUNING.md)** - Optimization tips and best practices

## 🚀 Quick Start

### Basic Setup with Circuit Breaker Enabled (Recommended)

```crystal
require "h2o"

# Enable circuit breaker globally
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

## 🏗️ Architecture Overview

H2O provides a complete HTTP/2 client implementation with integrated circuit breaker functionality:

### Core Components

1. **H2O::Client** - Main HTTP/2 client with circuit breaker integration
2. **H2O::Breaker** - Circuit breaker implementation with state management
3. **Persistence Adapters** - Pluggable state persistence (database, Redis, file)
4. **External Adapters** - Integration with existing circuit breaker solutions

### Circuit Breaker Features

- **Three States**: Closed (normal), Open (failing), Half-Open (testing recovery)
- **Configurable Thresholds**: Customizable failure thresholds and recovery timeouts
- **Thread-Safe**: Mutex-protected state management for concurrent access
- **Statistics Tracking**: Comprehensive success/failure tracking with timing data
- **Fiber Compatibility**: Native Crystal fiber support
- **Multiple Persistence Options**: Database, Redis, file, and in-memory storage
- **External Integration**: Public APIs for existing circuit breaker integration
- **Monitoring Callbacks**: State change and failure event notifications

## 📖 Documentation Sections

### 🎯 **[Integration Guide](./INTEGRATION_GUIDE.md)**
The most comprehensive resource for getting started with H2O. Covers:
- Basic configuration and setup
- Database persistence integration
- Monitoring and observability setup
- Migration from external circuit breakers
- Production best practices

### ⚙️ **[Configuration Examples](./CONFIGURATION_EXAMPLES.md)**
Real-world configuration examples including:
- Production setups with database persistence
- Microservices architecture configurations
- Service-specific circuit breaker tuning
- Environment-specific configurations
- Docker and Kubernetes deployments

### 📚 **[API Reference](./API_REFERENCE.md)**
Complete API documentation covering:
- H2O::Client methods and options
- H2O::Breaker configuration and state management
- Circuit breaker adapter interfaces
- Persistence adapter implementations
- Type definitions and exceptions

### 💾 **[Persistence Setup](./PERSISTENCE_SETUP.md)**
Detailed persistence configuration including:
- PostgreSQL schema and adapter implementation
- Redis single instance and cluster setups
- File-based persistence for development
- Custom persistence adapter development
- Migration strategies and performance optimization

## 🌟 Key Features

### Built-in Circuit Breaker
- **Zero Configuration**: Works out of the box with sensible defaults
- **Production Ready**: Enterprise-grade reliability patterns
- **Fiber Compatible**: Solves common Crystal concurrency issues
- **Highly Configurable**: Global, client, and request-level control

### Performance Optimized
- **Connection Pooling**: Efficient connection reuse and health checking
- **Protocol Caching**: HTTP/2 vs HTTP/1.1 support detection
- **Memory Efficient**: Optimized allocations and buffer reuse
- **Concurrent Safe**: Thread-safe operations with minimal locking

### Developer Friendly
- **Type Safe**: Full type annotations and Crystal safety features
- **Comprehensive Testing**: Extensive unit and integration test coverage
- **Clear Documentation**: Detailed guides and API references
- **Migration Support**: Easy migration from existing solutions

## 🔧 Installation

Add to your `shard.yml`:

```yaml
dependencies:
  h2o:
    github: nomadlabsinc/h2o
    version: "~> 1.0"
```

Then run:
```bash
shards install
```

## 🏃‍♂️ Basic Usage Examples

### Simple GET Request
```crystal
require "h2o"

client = H2O::Client.new
response = client.get("https://api.github.com/users/octocat")

if response && response.status == 200
  puts response.body
end
```

### POST with Circuit Breaker
```crystal
# Enable circuit breaker for specific request
response = client.post(
  "https://api.example.com/data",
  body: data.to_json,
  headers: {"Content-Type" => "application/json"},
  circuit_breaker: true
)
```

### Custom Circuit Breaker
```crystal
# Create circuit breaker with database persistence
persistence = DatabasePersistence.new(Database.connection)
breaker = H2O::Breaker.new(
  name: "payment_service",
  failure_threshold: 2,
  recovery_timeout: 120.seconds,
  persistence: persistence
)

client = H2O::Client.new(default_circuit_breaker: breaker)
```

## 🎯 Use Cases

### Microservices Communication
H2O is perfect for service-to-service communication in microservices architectures:
- Built-in reliability patterns prevent cascading failures
- Connection pooling optimizes resource usage
- Configurable per-service circuit breaker settings

### External API Integration
Ideal for integrating with third-party APIs:
- Circuit breakers prevent overwhelming failing services
- Persistent state survives application restarts
- Configurable timeouts and retry policies

### High-Traffic Applications
Designed for high-performance applications:
- Efficient HTTP/2 implementation
- Minimal allocation overhead
- Concurrent connection management

## 🛠️ Development and Testing

### Running Tests
```bash
crystal spec
```

### Code Formatting
```bash
crystal tool format
```

### Performance Testing
```bash
crystal run --release bench/performance_test.cr
```

## 📈 Performance Characteristics

- **Throughput**: Optimized for high request rates
- **Latency**: Minimal overhead when circuit breaker is disabled
- **Memory**: Efficient buffer management and connection reuse
- **Concurrency**: Thread-safe with minimal lock contention

## 🔍 Monitoring and Observability

H2O provides comprehensive monitoring capabilities:

### Built-in Metrics
- Request success/failure rates
- Circuit breaker state transitions
- Connection pool health
- Request timing and statistics

### Integration Points
- Prometheus metrics export
- Custom monitoring adapters
- State change callbacks
- Failure event notifications

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](../CONTRIBUTING.md) for details on:
- Code style and formatting requirements
- Testing procedures
- Pull request process
- Development setup

## 📄 License

H2O is released under the [MIT License](../LICENSE).

## 🆘 Support

- **Documentation**: Start with this documentation
- **Issues**: Report bugs and feature requests on [GitHub](https://github.com/nomadlabsinc/h2o/issues)
- **Discussions**: Join discussions in our [GitHub Discussions](https://github.com/nomadlabsinc/h2o/discussions)

---

## Next Steps

1. **New Users**: Start with the [Integration Guide](./INTEGRATION_GUIDE.md)
2. **Existing Users**: Check the [Configuration Examples](./CONFIGURATION_EXAMPLES.md) for advanced patterns
3. **API Developers**: Reference the [API Documentation](./API_REFERENCE.md)
4. **Production Deployments**: Follow the [Persistence Setup](./PERSISTENCE_SETUP.md) guide

Happy coding with H2O! 🚀