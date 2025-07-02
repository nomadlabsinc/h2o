# H2O HTTP/2 Compliance Tests

This directory contains HTTP/2 protocol compliance tests for the H2O client implementation.

## Native H2SPEC Compliance Tests

The primary compliance test suite is now implemented as native Crystal tests in the `native/` subdirectory. These tests provide comprehensive HTTP/2 protocol validation without external dependencies.

See [native/README.md](native/README.md) for detailed documentation including:
- Complete test inventory (192 tests)
- RFC section mapping
- H2SPEC coverage details
- Implementation patterns

## Overview

The native test suite covers:

- **HTTP/2 Protocol (RFC 7540)**: Connection management, frame handling, stream states, flow control, and HTTP semantics
- **HPACK Compression (RFC 7541)**: Header compression, dynamic table management, and security
- **Error Handling**: Protocol error detection and proper error responses

## Running the Tests

```bash
# Run all native compliance tests (192 tests)
crystal spec spec/compliance/native/

# Run specific test categories
crystal spec spec/compliance/native/connection_preface_spec.cr
crystal spec spec/compliance/native/stream_states_spec.cr

# Run in Docker (recommended)
docker compose run --rm app crystal spec spec/compliance/native/
```

## Test Organization

The compliance tests are organized by RFC section:

```
spec/compliance/native/
├── Core Protocol Tests (69 tests)
│   ├── connection_preface_spec.cr   # RFC 7540 §3.5
│   ├── frame_format_spec.cr         # RFC 7540 §4.1
│   ├── frame_size_spec.cr           # RFC 7540 §4.2
│   ├── stream_states_spec.cr        # RFC 7540 §5.1
│   ├── data_frames_spec.cr          # RFC 7540 §6.1
│   ├── headers_frames_spec.cr       # RFC 7540 §6.2
│   ├── priority_frames_spec.cr      # RFC 7540 §6.3
│   ├── rst_stream_frames_spec.cr    # RFC 7540 §6.4
│   └── settings_frames_spec.cr      # RFC 7540 §6.5
│
└── Comprehensive Tests (123 tests)
    ├── simple_hpack_*.cr            # RFC 7541 (HPACK)
    ├── simple_*_frames_spec.cr      # Frame-specific tests
    └── simple_*_spec.cr             # Protocol behavior tests
```

## Current Status

✅ **192 tests implemented**
- All tests passing
- Complete HTTP/2 protocol coverage
- HPACK compression validation
- Error handling verification

The native test suite has replaced the previous Go-based harness, providing better performance, reliability, and integration with Crystal's testing framework.