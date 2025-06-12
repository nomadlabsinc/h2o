# h2o

A high-performance HTTP/2 client for Crystal with full protocol compliance, connection pooling, and advanced features like HPACK compression and stream multiplexing. Optimized for production use with comprehensive CI testing.

## Features

- 🚀 **Full HTTP/2 Support**: Complete implementation of RFC 7540
- 🔐 **TLS with ALPN**: Automatic HTTP/2 negotiation via TLS ALPN
- 🗜️ **HPACK Compression**: RFC 7541 compliant header compression
- 🔀 **Stream Multiplexing**: Concurrent request handling over single connection
- 🏊 **Connection Pooling**: Efficient connection reuse and management
- 📊 **Flow Control**: Both connection and stream-level flow control
- ⚡ **High Performance**: Optimized for speed and low memory usage
- 🧪 **Comprehensive Tests**: Full test coverage with integration tests
- 🔄 **Circuit Breaker**: Built-in circuit breaker pattern for resilience

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  h2o:
    github: nomadlabsinc/h2o
    branch: main
```

Then run:

```bash
shards install
```

## Quick Start

```crystal
require "h2o"

# Create a client
client = H2O::Client.new

# Make a simple GET request
response = client.get("https://httpbin.org/get")
puts response.not_nil!.status  # => 200
puts response.not_nil!.body    # => JSON response

# Make a POST request with body
headers = H2O::Headers.new
headers["content-type"] = "application/json"
body = %q({"key": "value"})

response = client.post("https://httpbin.org/post", body, headers)
puts response.not_nil!.status  # => 200

# Clean up
client.close
```

## Advanced Usage

### Connection Pooling

The client automatically pools connections for better performance:

```crystal
client = H2O::Client.new(connection_pool_size: 20)

# Multiple requests to the same host will reuse the connection
response1 = client.get("https://api.example.com/users")
response2 = client.get("https://api.example.com/posts")  # Reuses connection
```

### Request Timeouts

Set custom timeouts for requests:

```crystal
client = H2O::Client.new(timeout: 10.seconds)

# This request will timeout after 10 seconds
response = client.get("https://slow-api.example.com/data")
```

### Custom Headers

Add custom headers to requests:

```crystal
headers = H2O::Headers.new
headers["authorization"] = "Bearer your-token"
headers["user-agent"] = "MyApp/1.0"

response = client.get("https://api.example.com/protected", headers)
```

### All HTTP Methods

```crystal
client = H2O::Client.new

# GET request
response = client.get("https://api.example.com/users")

# POST request
response = client.post("https://api.example.com/users", body)

# PUT request
response = client.put("https://api.example.com/users/1", body)

# DELETE request
response = client.delete("https://api.example.com/users/1")

# HEAD request
response = client.head("https://api.example.com/users")

# OPTIONS request
response = client.options("https://api.example.com/users")

# PATCH request
response = client.patch("https://api.example.com/users/1", body)
```

## Circuit Breaker

h2o includes built-in circuit breaker support for handling service failures gracefully. The circuit breaker prevents cascading failures and provides automatic recovery.

### Basic Circuit Breaker Usage

```crystal
# Enable circuit breaker globally
H2O.configure do |config|
  config.circuit_breaker_enabled = true
  config.default_failure_threshold = 5
  config.default_recovery_timeout = 60.seconds
end

client = H2O::Client.new

# Requests will now be protected by circuit breaker
response = client.get("https://api.example.com/data")
```

### Per-Client Circuit Breaker Configuration

```crystal
# Configure circuit breaker per client
client = H2O::Client.new(
  circuit_breaker_enabled: true,
  timeout: 10.seconds
)

# Circuit breaker will protect all requests from this client
response = client.get("https://unreliable-api.example.com/data")
```

### Per-Request Circuit Breaker Control

```crystal
client = H2O::Client.new

# Enable circuit breaker for specific request
response = client.get("https://api.example.com/data", circuit_breaker: true)

# Bypass circuit breaker for specific request
response = client.get("https://api.example.com/health", bypass_circuit_breaker: true)
```

### Custom Circuit Breaker

```crystal
# Create a custom circuit breaker with specific settings
custom_breaker = H2O::CircuitBreaker.new(
  name: "my_api_breaker",
  failure_threshold: 3,
  recovery_timeout: 30.seconds,
  timeout: 5.seconds
)

client = H2O::Client.new(
  default_circuit_breaker: custom_breaker
)
```

### External Circuit Breaker Integration

You can integrate h2o with your existing circuit breaker logic:

```crystal
class MyCustomCircuitBreakerAdapter
  include H2O::CircuitBreakerAdapter

  def initialize(@external_breaker : MyCircuitBreaker)
  end

  def should_allow_request? : Bool
    @external_breaker.state.closed?
  end

  def before_request(url : String, headers : H2O::Headers) : Bool
    @external_breaker.before_request(url)
  end

  def after_success(response : H2O::Response, duration : Time::Span) : Nil
    @external_breaker.record_success(duration)
  end

  def after_failure(exception : Exception, duration : Time::Span) : Nil
    @external_breaker.record_failure(exception, duration)
  end
end

# Use your custom adapter
client = H2O::Client.new(
  circuit_breaker_adapter: MyCustomCircuitBreakerAdapter.new(my_breaker)
)
```

### Persistence Options

Circuit breaker state can be persisted across application restarts:

```crystal
# Local file persistence
persistence = H2O::CircuitBreaker::LocalFileAdapter.new("./.circuit_breaker_data")

breaker = H2O::CircuitBreaker.new(
  "persistent_breaker",
  persistence: persistence
)

# In-memory persistence for testing
test_persistence = H2O::CircuitBreaker::InMemoryAdapter.new

test_breaker = H2O::CircuitBreaker.new(
  "test_breaker",
  persistence: test_persistence
)
```

### Monitoring Circuit Breaker State

```crystal
breaker = H2O::CircuitBreaker.new("monitored_breaker")

# Monitor state changes
breaker.on_state_change do |old_state, new_state|
  puts "Circuit breaker state changed: #{old_state} -> #{new_state}"
end

# Monitor failures
breaker.on_failure do |exception, statistics|
  puts "Circuit breaker failure: #{exception.message}"
  puts "Total failures: #{statistics.failure_count}"
end

# Access current state and statistics
puts "Current state: #{breaker.state}"
puts "Success count: #{breaker.statistics.success_count}"
puts "Failure count: #{breaker.statistics.failure_count}"
```

### Fiber Compatibility

The circuit breaker is designed to work correctly with Crystal's fiber system, solving the common issue where HTTP/2 operations fail in spawned fibers:

```crystal
# This now works correctly with circuit breaker enabled
channel = Channel(H2O::Response?).new

spawn do
  client = H2O::Client.new(circuit_breaker_enabled: true)
  response = client.get("https://api.example.com/data")
  channel.send(response)
end

result = channel.receive
```

## Low-Level API

For advanced use cases, you can work directly with connections:

```crystal
# Create a direct connection
connection = H2O::Connection.new("api.example.com", 443)

# Make requests on the connection
headers = H2O::Headers.new
headers["content-type"] = "application/json"

response = connection.request("GET", "/api/v1/data", headers)
puts response.not_nil!.status

# Send a ping to test connection
alive = connection.ping
puts "Connection alive: #{alive}"

# Close the connection
connection.close
```

## Architecture

h2o implements the complete HTTP/2 specification with these core components:

- **Frame Layer**: Low-level HTTP/2 frame parsing and serialization
- **HPACK**: Header compression and decompression
- **Stream Management**: HTTP/2 stream lifecycle and state management
- **Flow Control**: Window-based flow control at connection and stream levels
- **Connection Pooling**: Efficient connection reuse and management
- **TLS Integration**: Secure connections with ALPN negotiation

## Performance

h2o is designed for high performance with:

- Minimal memory allocations in hot paths
- Efficient byte manipulation for binary protocol handling
- Connection reuse to minimize TLS handshake overhead
- Concurrent request processing via stream multiplexing
- Optimized HPACK implementation with proper table management

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/nomadlabsinc/h2o.git
cd h2o

# Install dependencies
shards install

# Set up Git hooks for code quality
./scripts/setup-git-hooks.sh
```

### Pre-Commit Hooks

This project uses pre-commit hooks to ensure code quality standards:

```bash
# The hooks automatically check:
# ✓ Crystal code formatting (crystal tool format)
# ✓ Trailing newlines on all text files
# ✓ No trailing whitespace
# ✓ Crystal specs pass
# ✓ Crystal syntax is valid

# Run checks manually
./scripts/pre-commit-checks.sh

# Skip hooks for a commit (not recommended)
git commit --no-verify
```

### Building

```bash
# Build the library
crystal build src/h2o.cr

# Build with optimizations
crystal build --release src/h2o.cr

# Check syntax without building
crystal build --no-codegen src/h2o.cr

# Format code
crystal tool format

# Check formatting
crystal tool format --check
```

### Testing

h2o includes a comprehensive test suite with multiple testing approaches. We recommend using the Docker-based test runner for the most reliable and consistent testing experience.

#### Docker Test Runner (Recommended)

The project includes a comprehensive Docker-based test runner that ensures consistent testing across all environments:

```bash
# Run all tests (unit, integration, lint, build)
./scripts/test-runner.sh

# Run only unit tests (fast)
./scripts/test-runner.sh unit

# Run with verbose output and parallel execution
./scripts/test-runner.sh -v --parallel

# Run integration tests only
./scripts/test-runner.sh integration

# Run with coverage reporting
./scripts/test-runner.sh -c

# Run performance benchmarks
./scripts/test-runner.sh --performance

# Run only linting and formatting checks
./scripts/test-runner.sh lint

# Get help on all options
./scripts/test-runner.sh --help
```

#### Test Suites

The test runner supports multiple test suites:

- **unit**: Fast unit tests that don't require external services
- **integration**: Integration tests with real HTTP servers (nginx, httpbin)
- **performance**: Performance benchmarks and stress tests
- **lint**: Code formatting and linting checks
- **build**: Build verification and documentation generation

#### Native Crystal Testing

You can also run tests directly with Crystal (requires local setup):

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/h2o/client_spec.cr

# Run with coverage
crystal spec --coverage

# Run verbose
crystal spec --verbose

# Run specific test pattern
crystal spec --tag integration
```

#### CI Test Runner

For CI environments, use the specialized CI test runner:

```bash
# Run unit tests for CI
./scripts/ci_test_runner.sh unit

# Run integration tests for CI
./scripts/ci_test_runner.sh integration
```

#### Test Environment Setup

The Docker test runner automatically sets up the required test environment:

- **Crystal environment**: Uses `robnomad/crystal:dev-hoard` base image
- **Test servers**: nginx HTTP/2 server, httpbin for API testing
- **Dependencies**: All required Crystal shards and development tools
- **Network isolation**: Proper container networking for integration tests

#### Testing Best Practices

1. **Use Docker for consistency**: The Docker test runner ensures identical environments
2. **Run unit tests frequently**: Fast feedback during development
3. **Run full test suite before commits**: Ensures nothing is broken
4. **Use parallel testing**: Speed up test execution with `--parallel`
5. **Monitor coverage**: Use `--coverage` to ensure adequate test coverage
6. **Test in isolation**: Each test should be independent and not affect others

#### Test Configuration

Environment variables for test customization:

```bash
# Test timeout (default: 300 seconds)
export H2O_TEST_TIMEOUT=600

# Number of retries for flaky tests (default: 2)
export H2O_TEST_RETRIES=3

# Enable Docker BuildKit (default: 1)
export DOCKER_BUILDKIT=1
```

#### Debugging Tests

For debugging failing tests:

```bash
# Run with verbose output
./scripts/test-runner.sh -v unit

# Keep containers running after tests
./scripts/test-runner.sh --no-cleanup unit

# Run specific test file directly
docker run --rm -v $(pwd):/workspace -w /workspace --user root h2o-dev \
  bash -c "shards install && crystal spec spec/h2o/client_spec.cr --verbose"
```

### Docker Development

h2o uses a specialized development Docker image based on `robnomad/crystal:dev-hoard`:

```bash
# Build the development image
docker build -f Dockerfile.dev -t h2o-dev .

# Run development container
docker run -it --rm -v $(pwd):/workspace -w /workspace --user root h2o-dev bash

# Inside container
shards install
crystal spec

# Or use Docker Compose for integrated development
docker-compose -f docker-compose.yml up -d
docker-compose exec crystal bash
```

The development image includes:
- Crystal 1.16.3 with all dependencies
- Development tools (git, curl, vim, htop, etc.)
- Debugging tools (tshark, nghttp2)
- HTTP servers for testing (nginx, apache2, caddy)
- Node.js for HTTP/2 test servers

#### Development Workflow

```bash
# Quick development setup
./scripts/test-runner.sh unit  # Fast unit tests during development
./scripts/test-runner.sh -v    # Full test suite with verbose output

# Continuous testing during development
./scripts/test-runner.sh unit && echo "Tests passed!"

# Pre-commit testing
./scripts/test-runner.sh all --parallel
```

## Contributing

1. Fork it (<https://github.com/nomadlabsinc/h2o/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Please ensure all tests pass and code is properly formatted before submitting.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Authors

- [Nomad Labs Inc.](https://github.com/nomadlabsinc) - creator and maintainer

## Acknowledgments

- Crystal Language Team for the excellent language and standard library
- HTTP/2 specification authors (RFC 7540, RFC 7541)
- The Crystal community for inspiration and best practices
