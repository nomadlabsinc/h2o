# Crystal HTTP/2 Client Integration Guide

This guide explains how to properly integrate the h2-client-test-harness with Crystal HTTP/2 clients for compliance testing.

## Problem Statement

Many HTTP/2 client test suites incorrectly validate compliance by marking any error as "expected behavior". This leads to false positives where broken clients appear to pass all tests.

## Correct Approach

The h2-client-test-harness acts as a server that sends various valid and invalid HTTP/2 frames to test how clients handle them. The test runner must:

1. **Understand Expected Behavior**: Each test case has specific expected client behavior
2. **Validate Actual Behavior**: Check if the client's response matches expectations
3. **Properly Classify Errors**: Different error types indicate different compliance issues

## Test Categories and Expected Behaviors

### Success Cases
Tests where the client should successfully complete the request:
- Valid frames and protocol sequences
- Ignored unknown frame types/flags
- Proper SETTINGS acknowledgment

### Protocol Error Cases
Tests where the client should detect protocol violations:
- Invalid frame sequences
- Malformed frames
- Specification violations

### Frame Size Error Cases
Tests where frames exceed size limits:
- DATA/HEADERS frames > MAX_FRAME_SIZE
- Invalid frame lengths

### Flow Control Error Cases
Tests violating flow control:
- Data exceeding window size
- Window update overflow

### Compression Error Cases
HPACK-related errors:
- Invalid indexes
- Malformed Huffman encoding
- Table size violations

## Crystal Implementation Example

```crystal
# Define expected behaviors for each test
enum ExpectedBehavior
  Success
  ProtocolError
  FrameSizeError
  FlowControlError
  CompressionError
  StreamError
  GoAway
end

# Map test IDs to expected behaviors
TEST_CASES = [
  TestCase.new("6.5.3/2", "SETTINGS ACK expected", ExpectedBehavior::Success),
  TestCase.new("4.2/2", "DATA frame exceeds max size", ExpectedBehavior::FrameSizeError),
  TestCase.new("6.5/1", "SETTINGS with ACK and payload", ExpectedBehavior::ProtocolError),
  # ... more test cases
]

# Run test and validate behavior
def run_compliance_test(test_case)
  # Start harness container
  # ...
  
  begin
    # Try client connection
    client = MyHTTP2Client.new(host, port)
    response = client.request("GET", "/")
    client.close
    
    # Success - check if expected
    actual = "Success"
    passed = test_case.expected_behavior == ExpectedBehavior::Success
    
  rescue ex : ProtocolError
    actual = "ProtocolError"
    passed = test_case.expected_behavior.protocol_error?
    
  rescue ex : FrameSizeError
    actual = "FrameSizeError"
    passed = test_case.expected_behavior.frame_size_error?
    
  # ... handle other error types
  end
  
  TestResult.new(test_case, passed, actual)
end
```

## Common Mistakes to Avoid

1. **Don't mark all errors as success**
   ```crystal
   # WRONG - This hides compliance issues
   rescue ex
     passed = true  # Expected behavior
   ```

2. **Don't ignore error types**
   ```crystal
   # WRONG - Different errors mean different things
   rescue ex
     error_occurred = true
   ```

3. **Don't test client-side validation only**
   The harness tests how clients handle server behavior, not client-side frame generation.

## Running the Test Suite

1. Clone the harness repository:
   ```bash
   git clone https://github.com/nomadlabsinc/h2-client-test-harness.git
   ```

2. Build the Docker image:
   ```bash
   cd h2-client-test-harness
   docker build -t h2-client-test-harness .
   ```

3. Run your Crystal test suite:
   ```bash
   crystal spec spec/compliance/proper_harness_spec.cr
   ```

## Interpreting Results

- **High pass rate with proper validation**: Good compliance
- **100% pass rate**: Likely incorrect test implementation
- **Specific failures**: Areas needing implementation work

## Example Output

```
🧪 Running HTTP/2 Protocol Compliance Tests
================================================================================
[1/146] Running 3.5/1: Valid connection preface... ✅ PASS
[2/146] Running 3.5/2: Invalid connection preface... ✅ PASS
[3/146] Running 4.1/1: Valid frame format... ✅ PASS
[4/146] Running 4.2/2: DATA frame exceeds max size... ❌ FAIL (expected FrameSizeError, got Success)
...

📊 COMPLIANCE TEST RESULTS
================================================================================
Total Tests:  146
Passed:       89
Failed:       57
Success Rate: 61.0%

❌ Failed Tests:
  - 4.2/2: DATA frame exceeds max size
    Expected: FrameSizeError
    Actual:   Success
    (Client failed to detect oversized frame)
```

## Contributing

When adding new test cases:
1. Implement the server behavior in `harness/cases/`
2. Document the expected client behavior
3. Add the test case to the registry
4. Update test runners with proper validation

## References

- [RFC 7540 - HTTP/2](https://tools.ietf.org/html/rfc7540)
- [RFC 7541 - HPACK](https://tools.ietf.org/html/rfc7541)
- [h2spec](https://github.com/summerwind/h2spec) - Alternative compliance tool