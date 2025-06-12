# SSL Verification Configuration

H2O now supports configurable SSL certificate verification, which is particularly useful for local development and testing with self-signed certificates.

## Configuration Options

### 1. Environment Variable

Set the `H2O_VERIFY_SSL` environment variable to control SSL verification globally:

```bash
# Disable SSL verification
export H2O_VERIFY_SSL=false

# Enable SSL verification (default)
export H2O_VERIFY_SSL=true
```

Accepted values for disabling: `false`, `0`, `no`, `off`
Accepted values for enabling: `true`, `1`, `yes`, `on`

### 2. Global Configuration

Configure SSL verification programmatically:

```crystal
H2O.configure do |config|
  config.verify_ssl = false  # Disable SSL verification
end
```

### 3. Per-Client Configuration

Override SSL verification for specific client instances:

```crystal
# Create a client with SSL verification disabled
client = H2O::Client.new(verify_ssl: false)

# Make requests to servers with self-signed certificates
response = client.get("https://localhost:8443/api/endpoint")
```

## Usage Examples

### Local Integration Testing

For integration tests with local HTTPS servers using self-signed certificates:

```crystal
# In your test setup
client = H2O::Client.new(verify_ssl: false)
response = client.get("https://localhost:8443/test")
```

### Docker Compose Testing

When testing with Docker containers that use self-signed certificates:

```yaml
# docker-compose.yml
services:
  test:
    environment:
      - H2O_VERIFY_SSL=false
```

### CI/CD Pipeline

For CI environments where you need to test against staging servers with self-signed certificates:

```bash
# In your CI configuration
H2O_VERIFY_SSL=false crystal spec
```

## Security Considerations

⚠️ **WARNING**: Disabling SSL verification removes important security protections. Only disable SSL verification in:
- Local development environments
- Integration tests with known test servers
- Controlled testing environments

**Never disable SSL verification in production environments** as it makes your application vulnerable to man-in-the-middle attacks.

## Default Behavior

By default, SSL verification is **enabled** to ensure secure connections. The library will verify:
- Certificate validity
- Certificate chain of trust
- Hostname matching

This default behavior ensures that your production applications maintain proper security.
