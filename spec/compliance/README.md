# H2O HTTP/2 Compliance Tests

This directory contains HTTP/2 protocol compliance tests for the H2O client implementation.

## Overview

These tests are based on the comprehensive [h2-client-test-harness](https://github.com/nomadlabsinc/h2-client-test-harness) test suite, which implements all 146 H2SPEC test cases covering:

- **HTTP/2 Protocol (RFC 7540)**: Connection management, frame handling, stream states, flow control, and HTTP semantics
- **HPACK Compression (RFC 7541)**: Header compression, dynamic table management, and security
- **Generic Protocol Tests**: Cross-cutting protocol behavior validation

## Test Organization

The compliance tests are organized into multiple Crystal spec files:

- `h2spec_compliance_spec.cr` - Main HTTP/2 protocol compliance tests (Sections 3-8 of RFC 7540)
- `generic_tests_spec.cr` - Generic frame and protocol behavior tests
- `hpack_tests_spec.cr` - HPACK header compression tests (RFC 7541)
- `extra_tests_spec.cr` - Additional edge cases and comprehensive tests

## Running the Tests

To run all compliance tests:

```bash
crystal spec spec/compliance/
```

To run specific test categories:

```bash
# HTTP/2 protocol tests
crystal spec spec/compliance/h2spec_compliance_spec.cr

# HPACK compression tests
crystal spec spec/compliance/hpack_tests_spec.cr

# Generic protocol tests
crystal spec spec/compliance/generic_tests_spec.cr

# Extra edge case tests
crystal spec spec/compliance/extra_tests_spec.cr
```

## Test Implementation

Each test is implemented as a Crystal spec that:

1. Creates an H2O HTTP/2 client connection
2. Performs specific protocol operations
3. Verifies the client handles both valid and invalid scenarios correctly
4. Reports PASS/FAIL status

Tests marked as `pending` indicate features that require:
- Server-side support for sending malformed frames
- Features not yet implemented in the H2O client
- Complex protocol scenarios requiring specialized test infrastructure

## Test Coverage

The test suite covers all major areas of HTTP/2:

### Connection Management
- Connection preface exchange
- Settings negotiation
- Connection-level flow control
- GOAWAY handling

### Frame Processing
- All 10 frame types (DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PUSH_PROMISE, PING, GOAWAY, WINDOW_UPDATE, CONTINUATION)
- Frame size limits
- Unknown frame handling
- Malformed frame detection

### Stream Management
- Stream lifecycle (idle → open → half-closed → closed)
- Stream identifiers and concurrency limits
- Stream-level flow control
- Stream dependencies and prioritization

### Header Compression (HPACK)
- Static and dynamic table usage
- Huffman encoding
- Table size management
- Security protections (HPACK bomb prevention)

### HTTP Semantics
- Request/response exchange
- Pseudo-header fields
- Header field validation
- Method and status code handling

## Relationship to h2-client-test-harness

While these tests are inspired by the [h2-client-test-harness](https://github.com/nomadlabsinc/h2-client-test-harness), they are implemented as native Crystal tests that:

1. Test the H2O client directly without requiring external tools
2. Integrate with Crystal's built-in testing framework
3. Provide clear PASS/FAIL results for each scenario
4. Can be run as part of the regular test suite

The h2-client-test-harness project serves as the authoritative reference for HTTP/2 compliance testing, and these Crystal tests aim to cover the same scenarios in a way that's natural for Crystal development.

## Contributing

When adding new compliance tests:

1. Reference the specific RFC section being tested
2. Include the test case ID from h2spec (e.g., "6.5/1")
3. Clearly document expected behavior
4. Mark tests as `pending` if they require features not yet implemented
5. Ensure tests are deterministic and don't depend on timing

## Current Status

- ✅ 146 test cases defined
- ✅ Core protocol features tested
- ✅ HPACK compression tested
- ✅ Error handling verified
- ⏳ Some edge cases pending (require specialized server support)

The test suite provides comprehensive coverage of HTTP/2 protocol compliance and helps ensure the H2O client correctly implements the specification.