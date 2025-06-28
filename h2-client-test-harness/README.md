# HTTP/2 Client Test Harness

This repository contains a Go-based test harness for testing the compliance of HTTP/2 clients. It is inspired by [h2spec](https://github.com/summerwind/h2spec), but the logic is inverted: this harness acts as a server that sends specific, sometimes malformed, frames to a client to test the client's response.

This project also includes a reference "verifier" client, which is a known-good Go HTTP/2 client used to validate that the harness is behaving correctly.

## Usage

This harness is designed to be a general-purpose testing tool for any HTTP/2 client. To test your client:

1.  **Run the Harness (Server):**
    In one terminal, start the harness with the desired test case.
    ```shell
    go run ./cmd/harness --test=<test_case_id>
    ```

2.  **Run Your Client:**
    In another terminal, run your HTTP/2 client and make a request to `https://localhost:8080`.

3.  **Observe the Outcome:**
    Your client should receive the appropriate error or response from the harness.

### Verifying the Harness Itself

To verify that the harness is working correctly, you can run it against the included verifier client:

1.  **Run the Harness (Server):**
    ```shell
    go run ./cmd/harness --test=<test_case_id> &
    ```

2.  **Run the Verifier (Client):**
    ```shell
    go run ./cmd/verifier --test=<test_case_id>
    ```
    If the verifier exits with a `status 0`, the harness is correctly implementing the test case.

## Using the Harness for HTTP/2 Client Development

This harness can be used to test HTTP/2 clients in any language. The harness acts as a malicious/non-compliant server that sends specific frames to test client compliance.

### Crystal HTTP/2 Client Example

To test a Crystal HTTP/2 client implementation:

1. **Start the test harness server:**
   ```bash
   go run . --test=6.5/1
   ```

2. **Create a Crystal test client** (`test_client.cr`):
   ```crystal
   require "http/client"
   require "openssl"
   
   # Configure SSL context to accept self-signed certificates
   context = OpenSSL::SSL::Context::Client.new
   context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
   
   # Create HTTP/2 client
   client = HTTP::Client.new("localhost", 8080, tls: context)
   client.before_request { |req| req.headers["Connection"] = "Upgrade, HTTP2-Settings" }
   
   begin
     response = client.get("/")
     puts "Response: #{response.status_code}"
   rescue ex
     puts "Error (expected): #{ex.message}"
     exit 1 if ex.message.includes?("FRAME_SIZE_ERROR")
   end
   ```

3. **Run the Crystal client:**
   ```bash
   crystal run test_client.cr
   ```

4. **Verify expected behavior:**
   - For protocol error tests (like `6.5/1`): Client should detect the error and close the connection
   - For compliance tests: Client should handle the frame correctly and maintain the connection
   - Exit codes: 0 = test passed, 1 = test failed

### Test Categories

- **Protocol Errors**: Tests expect the client to detect violations and close the connection with appropriate error codes
- **Compliance Tests**: Tests verify the client handles valid but edge-case frames correctly
- **HPACK Tests**: Tests verify header compression/decompression compliance

### Available Test IDs

Run the harness without arguments to see all available test cases:
```bash
go run . --test=""
```

## Docker Usage

For CI/CD and reproducible testing environments, use the Docker image:

### Quick Start with Docker

```bash
# Build the image
docker build -t h2-test-harness .

# List all 146 available tests
docker run --rm h2-test-harness --list

# Run a specific test
docker run --rm h2-test-harness --test=6.5/2

# Run complete test suite verification  
docker run --rm h2-test-harness --verify-all

# Run harness only (for external client testing)
docker run --rm -p 8080:8080 h2-test-harness --harness-only --test=6.5/1
```

### Docker Test Commands

- `--list`: Display all 146 available test cases
- `--test=<id>`: Run specific test case with full harness + verifier validation
- `--verify-all`: Execute complete test suite (all 146 tests) with pass/fail summary
- `--harness-only --test=<id>`: Run harness server only for external client testing

## Test Coverage

This harness implements **146 comprehensive H2SPEC test cases** covering 100% of HTTP/2 protocol compliance scenarios from RFC 7540 (HTTP/2) and RFC 7541 (HPACK).

### 📋 Complete Test Documentation

For a comprehensive breakdown of all test cases, expected outcomes, and RFC coverage:

**[📖 View Complete RFC Test Cases Documentation](./docs/RFC_TEST_CASES.md)**

### Quick Overview

| Category | Count | Coverage |
|----------|-------|----------|
| **HTTP/2 Protocol** (RFC 7540) | 118 | Connection, frames, streams, flow control, HTTP semantics |
| **HPACK Compression** (RFC 7541) | 13 | Header compression and dynamic table management |
| **Generic Protocol** | 15 | Cross-cutting protocol behavior validation |
| **TOTAL** | **146** | **100% H2SPEC Coverage** |

### Available Test Cases

To see all 146 available test cases:
```bash
# Local execution
go run . --test=""

# Docker execution  
docker run --rm h2-test-harness --list
```
