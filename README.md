# h2o

A high-performance HTTP/2 client for Crystal with full protocol compliance, connection pooling, and advanced features like HPACK compression and stream multiplexing.

## Features

- 🚀 **Full HTTP/2 Support**: Complete implementation of RFC 7540
- 🔐 **TLS with ALPN**: Automatic HTTP/2 negotiation via TLS ALPN
- 🗜️ **HPACK Compression**: RFC 7541 compliant header compression
- 🔀 **Stream Multiplexing**: Concurrent request handling over single connection
- 🏊 **Connection Pooling**: Efficient connection reuse and management
- 📊 **Flow Control**: Both connection and stream-level flow control
- ⚡ **High Performance**: Optimized for speed and low memory usage
- 🧪 **Comprehensive Tests**: Full test coverage with integration tests

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  h2o:
    github: nomadlabsinc/h2o
    version: ~> 0.1.0
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

### Building

```bash
# Install dependencies
shards install

# Build the library
crystal build src/h2o.cr

# Run tests
crystal spec

# Run linter
./bin/ameba

# Format code
crystal tool format
```

### Testing

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/h2o/client_spec.cr

# Run with coverage
crystal spec --coverage
```

### Docker Development

Use the official Crystal image for development:

```bash
# Pull the official Crystal image
docker pull crystallang/crystal:1.16.0

# Run development container
docker run -it --rm -v $(pwd):/workspace crystallang/crystal:1.16.0 bash

# Inside container
cd /workspace
shards install
crystal spec
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