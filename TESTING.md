# Testing Guide for H2O

This document provides comprehensive guidelines for testing the H2O HTTP/2 client library.

## Overview

H2O uses a multi-tier testing approach designed to ensure reliability, performance, and correctness across different environments:

1. **Unit Tests**: Fast, isolated tests for individual components
2. **Integration Tests**: End-to-end tests with real HTTP servers
3. **Performance Tests**: Benchmarks and stress testing
4. **Lint/Format Tests**: Code quality and style enforcement
5. **Build Tests**: Compilation and documentation verification

## Test Runner

### Primary Test Runner

The main test runner is `./scripts/test-runner.sh`, which provides a comprehensive Docker-based testing environment:

```bash
# Basic usage
./scripts/test-runner.sh [OPTIONS] [SUITE]

# Examples
./scripts/test-runner.sh                    # Run all tests
./scripts/test-runner.sh unit               # Unit tests only
./scripts/test-runner.sh -v --parallel      # Verbose parallel execution
./scripts/test-runner.sh integration -c     # Integration tests with coverage
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Enable verbose output for debugging |
| `-p, --parallel` | Run tests in parallel where possible |
| `-c, --coverage` | Generate test coverage reports |
| `--no-integration` | Skip integration tests |
| `--no-lint` | Skip linting checks |
| `--no-format` | Skip format checking |
| `--no-build` | Skip build checks |
| `--no-cleanup` | Keep Docker containers after tests |
| `--performance` | Include performance tests |
| `--docs` | Build documentation |

### Test Suites

#### Unit Tests (`unit`)
Fast tests that don't require external dependencies:
- Component behavior testing
- Algorithm correctness
- Error handling
- Edge cases

```bash
./scripts/test-runner.sh unit
```

#### Integration Tests (`integration`)
End-to-end tests with real HTTP servers:
- HTTP/2 protocol compliance
- TLS/ALPN negotiation
- Connection pooling
- Real-world scenarios

```bash
./scripts/test-runner.sh integration
```

#### Performance Tests (`performance`)
Benchmarking and stress testing:
- Throughput measurements
- Memory usage analysis
- Connection scaling
- HPACK performance

```bash
./scripts/test-runner.sh --performance
```

#### Lint Tests (`lint`)
Code quality enforcement:
- Crystal formatting (`crystal tool format`)
- Ameba linting
- Style guide compliance

```bash
./scripts/test-runner.sh lint
```

#### Build Tests (`build`)
Compilation and documentation:
- Release build verification
- Documentation generation
- Syntax validation

```bash
./scripts/test-runner.sh build
```

## Test Environment

### Docker-based Testing

The recommended approach uses Docker containers for consistent, reproducible testing:

**Base Image**: `robnomad/crystal:dev-hoard`
- Crystal 1.16.3 runtime
- Alpine Linux with optimized packages
- Development and debugging tools
- HTTP servers for testing

**Test Servers**:
- **nginx**: HTTP/2 and HTTP/1.1 server for protocol testing
- **httpbin**: HTTP API testing service
- **caddy**: Modern HTTP/2 server with advanced features

### Local Testing

For rapid development, you can run tests locally:

```bash
# Prerequisites: Crystal 1.16.3+, development dependencies
shards install
crystal spec

# Specific test files
crystal spec spec/h2o/client_spec.cr --verbose
```

## Writing Tests

### Test Structure

Follow Crystal's standard testing conventions:

```crystal
require "../spec_helper"

describe H2O::MyComponent do
  describe "#method_name" do
    it "should behave correctly" do
      # Arrange
      component = H2O::MyComponent.new

      # Act
      result = component.method_name(input)

      # Assert
      result.should eq(expected_value)
    end
  end
end
```

### Test Categories

#### Unit Tests

Place in `spec/h2o/` directory:

```crystal
# spec/h2o/component_spec.cr
describe H2O::Component do
  it "handles basic functionality" do
    component = H2O::Component.new
    component.process("input").should eq("output")
  end

  it "handles edge cases" do
    component = H2O::Component.new
    expect_raises(H2O::InvalidInputError) do
      component.process("")
    end
  end
end
```

#### Integration Tests

Place in `spec/integration/` directory:

```crystal
# spec/integration/http2_client_spec.cr
describe "HTTP/2 Client Integration" do
  it "connects to real HTTP/2 server" do
    client = H2O::Client.new
    response = client.get("https://httpbin.org/get")

    response.should_not be_nil
    response.not_nil!.status.should eq(200)
    response.not_nil!.headers["content-type"].should contain("json")
  end
end
```

#### Performance Tests

Place in `spec/performance/` directory:

```crystal
# spec/performance/throughput_spec.cr
describe "Throughput Performance" do
  it "handles high request volume" do
    client = H2O::Client.new

    start_time = Time.monotonic

    (1..1000).each do |i|
      response = client.get("https://httpbin.org/get?id=#{i}")
      response.should_not be_nil
    end

    duration = Time.monotonic - start_time
    requests_per_second = 1000.0 / duration.total_seconds

    # Assert minimum performance threshold
    requests_per_second.should be > 50.0
  end
end
```

### Test Best Practices

#### 1. Test Independence
Each test should be completely independent:

```crystal
# Good: Each test sets up its own state
describe H2O::Client do
  it "test A" do
    client = H2O::Client.new
    # test logic
    client.close
  end

  it "test B" do
    client = H2O::Client.new
    # test logic
    client.close
  end
end
```

#### 2. Descriptive Test Names
Use clear, descriptive test names:

```crystal
# Good: Describes behavior and context
it "returns 404 when requesting non-existent resource" do
  # test logic
end

# Bad: Vague or technical
it "test_get_request" do
  # test logic
end
```

#### 3. Proper Setup and Teardown
Clean up resources properly:

```crystal
describe H2O::Connection do
  property connection : H2O::Connection?

  before_each do
    @connection = H2O::Connection.new("example.com", 443)
  end

  after_each do
    @connection.try(&.close)
  end

  it "performs operations" do
    connection = @connection.not_nil!
    # test logic
  end
end
```

#### 4. Mock External Dependencies
Use mocks for external services in unit tests:

```crystal
# Use test doubles for external dependencies
class MockHTTPServer
  def initialize(@responses : Array(String))
  end

  def next_response
    @responses.shift? || "default response"
  end
end
```

#### 5. Test Error Conditions
Always test error scenarios:

```crystal
describe H2O::Client do
  it "handles network timeout gracefully" do
    client = H2O::Client.new(timeout: 0.1.seconds)

    expect_raises(H2O::TimeoutError) do
      client.get("https://slow-server.example.com/delay/10")
    end
  end
end
```

## CI Integration

### GitHub Actions

Tests run automatically on:
- Pull requests to `main`
- Pushes to `main`
- Manual workflow dispatch

The CI pipeline includes:
1. **Unit Tests**: Fast feedback on basic functionality
2. **Integration Tests**: Full protocol compliance testing
3. **Lint Checks**: Code quality enforcement
4. **Build Verification**: Compilation and documentation

### CI-Specific Testing

The CI environment uses specialized scripts:

```bash
# CI test runner with optimized timeouts and retries
./scripts/ci_test_runner.sh unit
./scripts/ci_test_runner.sh integration
```

## Troubleshooting

### Common Issues

#### 1. Docker Permission Errors
```bash
# Solution: Run containers as root
docker run --rm -v $(pwd):/workspace --user root h2o-dev [command]
```

#### 2. Test Server Connection Failures
```bash
# Check test servers are running
cd spec/integration
docker compose ps

# Restart test servers
docker compose down
docker compose up -d
```

#### 3. Flaky Integration Tests
```bash
# Run with retries
export H2O_TEST_RETRIES=3
./scripts/test-runner.sh integration

# Debug with verbose output
./scripts/test-runner.sh -v integration
```

#### 4. Memory Issues in Performance Tests
```bash
# Increase Docker memory limits
# Add to docker run command: --memory=4g --memory-swap=4g
```

### Debug Mode

Enable debug output for detailed troubleshooting:

```bash
# Enable verbose output
./scripts/test-runner.sh -v [suite]

# Keep containers running for inspection
./scripts/test-runner.sh --no-cleanup [suite]

# Manual container inspection
docker run -it --rm -v $(pwd):/workspace --user root h2o-dev bash
```

## Coverage Analysis

### Generating Coverage Reports

```bash
# Generate coverage for all tests
./scripts/test-runner.sh -c

# Coverage for specific suite
./scripts/test-runner.sh unit -c
```

### Coverage Targets

Maintain these minimum coverage levels:
- **Overall Coverage**: ≥ 90%
- **Core HTTP/2 Logic**: ≥ 95%
- **Public API**: ≥ 95%
- **Error Handling**: ≥ 85%

## Performance Benchmarks

### Benchmark Suites

1. **Throughput Tests**: Requests per second under load
2. **Memory Tests**: Memory usage under various conditions
3. **Connection Tests**: Connection pooling efficiency
4. **HPACK Tests**: Header compression performance

### Running Benchmarks

```bash
# Run all performance tests
./scripts/test-runner.sh --performance

# Specific benchmark category
crystal spec spec/performance/throughput_spec.cr --verbose
```

### Performance Targets

- **Throughput**: ≥ 1000 requests/second (simple GET requests)
- **Memory**: ≤ 50MB for 100 concurrent connections
- **Connection Reuse**: ≥ 95% connection reuse rate
- **HPACK Efficiency**: ≥ 70% header compression ratio

## Continuous Integration

### Pre-commit Testing

Before committing code, run:

```bash
# Quick validation
./scripts/test-runner.sh unit

# Full validation
./scripts/test-runner.sh --parallel

# Pre-commit hook integration
./scripts/setup-git-hooks.sh
```

### Release Testing

Before releases, run the complete test suite:

```bash
# Comprehensive testing
./scripts/test-runner.sh all --parallel --coverage --performance --docs
```

This ensures all functionality works correctly before release.
