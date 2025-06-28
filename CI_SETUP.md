# H2O CI Setup - Deterministic Docker-based Testing

## Overview

H2O uses a deterministic Docker-based CI pipeline that runs exactly the same way locally and in GitHub Actions. All tests run inside Docker containers on **ubicloud-standard-4** instances to ensure consistent, reproducible results.

## CI Jobs

### 1. Unit Tests (5 minutes)
- **Purpose**: Core functionality testing
- **Environment**: Docker container with Crystal
- **Tests**: Frame validation, HPACK, client functionality
- **Command**: `docker compose run --rm app crystal spec spec/h2o/`

### 2. Strict Validation Tests (5 minutes) 
- **Purpose**: Validate HTTP/2 strict compliance implementation
- **Tests**:
  - Fast compliance validation (15 tests, ~7ms)
  - HPACK validation (24 tests, ~6ms)
  - Frame validation (7 tests, ~3ms)
  - CVE-2024-27316 protection tests
- **Key Features Tested**:
  - ✅ Frame size validation - DoS prevention
  - ✅ Stream ID validation - RFC 7540 compliance
  - ✅ Flow control validation - Window overflow protection
  - ✅ HPACK validation - Compression bomb prevention
  - ✅ CONTINUATION validation - CVE-2024-27316 protection

### 3. Integration Tests (10 minutes)
- **Purpose**: End-to-end functionality testing
- **Environment**: Docker with external services (httpbin, nghttpd)
- **Tests**: Circuit breakers, connection pooling, SSL verification, HTTP/1 fallback

### 4. H2SPEC Compliance Validation (8 minutes)
- **Purpose**: Validate against h2spec test harness
- **Approach**: Focused subset of critical tests (not full 146 suite)
- **Tests**: Connection preface, frame size, SETTINGS, flow control
- **Validation**: Demonstrates strict validation working with real h2spec scenarios

### 5. Build and Lint (5 minutes)
- **Purpose**: Code quality and build verification
- **Tools**: Crystal compiler, Ameba linter
- **Checks**: Successful compilation, code style compliance

## Key Features

### Deterministic Environment
- **Same Docker containers** used locally and in CI
- **ubicloud-standard-4 instances** for consistent performance
- **Docker Buildx** for reproducible builds
- **Short timeouts** (5-10 minutes) for fast feedback

### Strict Validation Focus
- **Production-ready security** testing
- **RFC 7540 compliance** validation
- **DoS attack prevention** verification
- **Fast performance** validation (< 1ms frame validation)

### Practical Testing Strategy
- **No flaky h2spec networking** - Uses focused validation instead
- **Fast execution** - All jobs complete in under 10 minutes
- **Reliable results** - Docker ensures consistent environment
- **Comprehensive coverage** - 50+ tests across all validation modules

## Local Testing

You can run the exact same tests locally:

```bash
# Run all validation tests
crystal run scripts/validate_strict_compliance.cr

# Run specific test suites
docker compose run --rm app crystal spec spec/compliance_validation_spec.cr --verbose
docker compose run --rm app crystal spec spec/h2o/hpack/ --verbose  
docker compose run --rm app crystal spec spec/h2o/frames/frame_spec.cr --verbose

# Run unit tests
docker compose run --rm app crystal spec spec/h2o/

# Run integration tests  
docker compose run --rm app crystal spec spec/integration/

# Build and lint
docker compose run --rm app crystal build src/h2o.cr
docker compose run --rm app ameba src/
```

## Performance Characteristics

- **Unit Tests**: < 5 minutes, 20+ tests
- **Strict Validation**: < 5 minutes, 50+ tests  
- **Integration Tests**: < 10 minutes, 8 test suites
- **Compliance Validation**: < 8 minutes, focused h2spec testing
- **Build/Lint**: < 5 minutes

## Success Criteria

✅ **All tests must pass** - No partial success rates
✅ **Fast execution** - Under 10 minutes per job
✅ **Deterministic results** - Same behavior locally and in CI
✅ **Comprehensive coverage** - All validation modules tested
✅ **Production ready** - Validates security and RFC compliance

## Monitoring

- **GitHub Actions UI** shows real-time progress
- **Colored output** for easy status identification  
- **Detailed logs** for debugging failures
- **Artifact uploads** for test results
- **Clear success/failure indicators**

This CI setup ensures H2O's strict HTTP/2 validation is thoroughly tested and ready for production use!