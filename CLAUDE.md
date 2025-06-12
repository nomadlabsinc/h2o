# Claude Operating Instructions for Crystal Development

Adhere to these principles to ensure a high-quality, performant, and maintainable Crystal app:

1.  **Idiomatic Crystal:**
    *   Follow Crystal's [Coding Style Guide](https://crystal-lang.org/reference/1.16/conventions/coding_style.html) rigorously (e.g., `snake_case` for methods/variables, `PascalCase` for classes/modules, `SCREAMING_SNAKE_CASE` for constants).
    *   Leverage Crystal's concurrency primitives (`Channel`, `Fiber`, `Mutex`) appropriately.
    *   Prioritize type safety; use explicit type annotations where beneficial for clarity or performance, especially in performance-critical paths or public APIs.
    *   Employ `raise` for exceptional conditions and `begin...rescue` for robust error handling.
    *   Avoid unnecessary use of `begin` when working in crystal and ruby with exception handling.

2.  **Performance Focus:**
    *   Consult Crystal's [Performance Guide](https://crystal-lang.org/reference/1.16/guides/performance.html).
    *   Minimize allocations, especially in hot loops (e.g., frame parsing/serialization, HPACK operations). Reuse buffers where possible.
    *   Optimize byte manipulation: use `IO#read_bytes` and `IO#write_bytes` efficiently. Avoid unnecessary `String` conversions in binary protocols.
    *   Profile frequently using `crystal build --release --no-debug` and tools like `perf` to identify bottlenecks.
    *   Be mindful of fiber context switching overhead; ensure fibers are used strategically for concurrency, not for trivial tasks.
    *   Connection pooling (as noted in development tasks) is a critical performance optimization to minimize TLS handshake and connection overhead.

3.  **HTTP/2 Protocol Performance Optimizations (CRITICAL):**
    *   **Use hash-based lookups instead of linear search** - Replace O(n) operations with O(1) hash lookups, especially in HPACK table operations
    *   **Implement connection health validation** - Check stream capacity and connection state before reusing connections to prevent unnecessary new connections
    *   **Use buffer pooling for frame operations** - Reuse byte buffers to reduce GC pressure during frame serialization/deserialization
    *   **Cache protocol support per host** - Store HTTP/2 vs HTTP/1.1 support information to avoid redundant negotiation attempts
    *   **Optimize fiber usage** - Minimize fiber creation overhead, consider shared fiber pools for high-frequency operations
    *   **Implement adaptive buffer sizing** - Size buffers based on expected data patterns rather than fixed large allocations

4.  **Test-Driven Development (TDD):**
    *   Write tests *before* or concurrently with implementation.
    *   Ensure high unit test coverage for all components.
    *   Develop robust integration tests against real and mock servers.
    *   **Success Rate in Tests:**
        *   Tests must always aim for 100% success rate
        *   Avoid partial success metrics like:
            ```crystal
            # bad!
            success_rate = successful_count.to_f / results.size
            129        success_rate.should be >= 0.87 # At least 87% success rate (13/15 requests)
            ```
        *   Strive for complete test coverage and full passing status

5.  **Observability & Debugging:**
    *   Integrate Crystal's `Log` module for structured logging. Define log levels (e.g., `DEBUG`, `INFO`, `WARN`, `ERROR`) and allow configuration via environment variables (e.g., `LOG_LEVEL`).
    *   Utilize `crystal run --runtime-trace` (refer to [Runtime Tracing](https://crystal-lang.org/reference/1.16/guides/runtime_tracing.html)) for debugging concurrency issues.
    *   `tshark` or `Wireshark` are invaluable for inspecting raw TLS and HTTP/2 traffic.

6.  **Security Considerations:**
    *   Ensure proper certificate validation (trust store, SNI). Consider options for custom CA certificates or certificate pinning if required by the application's security posture.
    *   Protect against common HTTP/2 denial-of-service vectors (e.g., `SETTINGS` flood, `PRIORITY` flood, oversized frames).

7.  **Timing and Concurrency:**
    *   Always use `sleep(0.1.seconds)`, not `sleep(0.1)` or `sleep 0.1`

8.  **Docker Practices:**
    *   Don't use version fields in docker-compose -- that's outdated.
    *   When running tests, run them inside Docker to allow dependencies like HTTP and HTTP2 servers to run correctly.

## 🚨 CRITICAL: Code Quality and Formatting Standards

[... rest of the file remains the same ...]
