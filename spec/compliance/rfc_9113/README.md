# RFC 9113 Compliance Tests

This directory contains tests and documentation to ensure H2O's compliance with RFC 9113 (HTTP/2).

## Purpose

RFC 9113 obsoletes RFC 7540 and introduces important changes that require specific testing:

1. **Header field name validation** - Stricter character restrictions
2. **Content-Length semantics** - Validation with END_STREAM flags  
3. **Priority signaling deprecation** - RFC 7540 priorities are deprecated
4. **h2c upgrade deprecation** - HTTP/1.1 upgrade mechanism deprecated
5. **Error handling clarifications** - More precise error code requirements

## Test Structure

- `header_field_validation_spec.cr` - Tests RFC 9113 header name/value validation
- `content_length_semantics_spec.cr` - Tests Content-Length with END_STREAM
- `priority_deprecation_spec.cr` - Tests for deprecated priority signaling
- `error_handling_spec.cr` - Tests RFC 9113 error code requirements
- `connection_preface_spec.cr` - Tests connection preface compliance

## Running Tests

```bash
# Run all RFC 9113 compliance tests
docker compose run --rm app crystal spec spec/compliance/rfc_9113/

# Run specific test
docker compose run --rm app crystal spec spec/compliance/rfc_9113/header_field_validation_spec.cr
```

## h2spec Integration

Use h2spec for comprehensive HTTP/2 protocol compliance testing:

```bash
# Run h2spec against H2O server
docker compose run --rm h2spec -h nghttpd -p 4430 -k -t
```

## Compliance Status

- ✅ Connection preface (already compliant)
- ❌ Header field name validation (needs fix)
- ❌ Content-Length with END_STREAM (needs implementation)  
- ⚠️ Priority signaling (needs deprecation warnings)
- ⚠️ Terminology updates (needs field block terminology)