# TLS Segmentation Fault Analysis

## Problem Description
The H2O HTTP/2 client experiences a segmentation fault after 7 successful TLS connections. The 8th connection attempt triggers a segfault. When TLS is disabled, the tests hang instead of segfaulting.

## Root Cause Analysis

### 1. **OpenSSL Thread Safety Issues**
Crystal's OpenSSL bindings might not be fully thread-safe, especially when:
- Multiple SSL contexts are created/destroyed rapidly
- SSL sockets are closed while operations are pending
- Garbage collection occurs during SSL operations

### 2. **Resource Leaks**
Several potential resource leaks were identified:

#### TCP Socket Leak
In the original `TlsSocket` implementation, if SSL handshake fails, the TCP socket might not be properly closed:
```crystal
tcp_socket = TCPSocket.new(hostname, port)
@socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: sni_name)
# If this fails, tcp_socket is not closed
```

#### Fiber Leak
The connection timeout fiber might not be properly terminated:
```crystal
fiber = spawn do
  # This fiber might continue running if channel is not closed
end
```

### 3. **Global State Accumulation**
The global `TLSCache` instance accumulates state across connections:
- Certificate validation results
- TLS session entries
- SNI cache entries

This could lead to memory growth and potential corruption after multiple connections.

### 4. **Missing OpenSSL Cleanup**
The code doesn't explicitly:
- Free SSL contexts
- Clear SSL error queues
- Handle SSL session cleanup

## Fixes Applied

### 1. **Proper Resource Management**
- Store TCP socket reference for cleanup
- Ensure TCP socket is closed even if SSL setup fails
- Add proper channel cleanup to prevent fiber leaks

### 2. **Enhanced Close Method**
- Close SSL socket before TCP socket
- Add defensive checks for closed sockets
- Add small delay for OpenSSL cleanup

### 3. **Mutex Protection**
- All socket operations are protected by mutex
- Prevent concurrent access during close

### 4. **Finalizer Addition**
- Add `finalize` method for GC cleanup
- Ensures resources are freed even if `close` is not called

## Test Results

The fix should allow:
- More than 7 consecutive TLS connections
- Proper cleanup of resources
- No memory leaks or segfaults

## Recommendations

1. **Consider OpenSSL Session Caching**
   - Implement proper SSL session reuse
   - Reduce overhead of repeated connections

2. **Add OpenSSL Error Queue Clearing**
   - Call `OpenSSL.errors.clear` after operations
   - Prevent error accumulation

3. **Monitor Memory Usage**
   - Add instrumentation to track SSL object lifecycle
   - Monitor for memory growth patterns

4. **Crystal OpenSSL Bindings Enhancement**
   - Consider contributing improvements to Crystal's OpenSSL bindings
   - Add missing session management APIs

## Testing

Run the following tests to verify the fix:
```bash
crystal spec spec/debug_segfault_spec.cr
crystal spec spec/tls_segfault_fix_spec.cr
```

Monitor for:
- Successful connections beyond the 7th attempt
- No segmentation faults
- Proper resource cleanup