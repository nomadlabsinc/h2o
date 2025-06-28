# Important Update: Proper Client Compliance Testing

## ⚠️ Common Testing Mistake

Many HTTP/2 client test suites incorrectly validate compliance by treating **any error as success**. This leads to broken clients appearing to have "100% compliance" when they actually fail to handle the protocol correctly.

### The Problem

```crystal
# INCORRECT - This approach hides compliance issues
begin
  client.connect_and_request()
rescue ex
  # Marking ALL errors as "expected behavior" is wrong!
  test_passed = true  
end
```

This pattern makes every test pass regardless of whether the client correctly handles the protocol.

### The Solution

Test runners must understand what behavior each test expects:

1. **Success Tests**: Client should complete the request successfully
2. **Error Detection Tests**: Client should detect specific protocol violations
3. **Proper Error Classification**: Different errors indicate different compliance issues

## Correct Implementation

See the [Crystal Integration Guide](docs/CRYSTAL_INTEGRATION.md) for a complete example of proper compliance testing.

### Quick Example

```crystal
# Define expected behavior for each test
case test_id
when "6.5.3/2"  # SETTINGS ACK test
  # Client SHOULD successfully handle this
  expected = :success
when "4.2/2"    # Oversized frame test  
  # Client SHOULD detect frame size error
  expected = :frame_size_error
when "6.5/1"    # Invalid SETTINGS test
  # Client SHOULD detect protocol error
  expected = :protocol_error
end

# Run test and validate
begin
  client.request()
  actual = :success
rescue FrameSizeError
  actual = :frame_size_error
rescue ProtocolError
  actual = :protocol_error
end

# Compare actual vs expected
test_passed = (actual == expected)
```

## Why This Matters

- **False Positives**: Broken clients appear compliant
- **Hidden Bugs**: Real protocol violations go undetected
- **Security Issues**: Malformed frames might crash or exploit clients
- **Interoperability**: Non-compliant clients fail with real servers

## For Test Suite Authors

1. **Map test IDs to expected behaviors** - Each test has a specific purpose
2. **Classify client errors properly** - Different exceptions mean different things
3. **Validate actual vs expected** - Don't assume all errors are correct
4. **Expect some failures** - 100% pass rate indicates bad tests, not good compliance

## Example Results

### Incorrect Testing (Everything Passes)
```
✅ 146/146 tests passed (100%)
```
*This likely means your tests are wrong!*

### Correct Testing (Real Validation)
```
✅ 89/146 tests passed (61%)
❌ 57 tests failed:
  - 4.2/2: Client didn't detect oversized frame
  - 6.5/1: Client accepted invalid SETTINGS
  ... (specific failures that need fixing)
```

## Resources

- [Crystal Integration Guide](docs/CRYSTAL_INTEGRATION.md) - Full implementation example
- [RFC Test Cases](docs/RFC_TEST_CASES.md) - What each test validates
- [Example Test Runner](crystal-example/proper_harness_spec.cr) - Reference implementation