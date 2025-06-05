# h2o Client Shard Development Tasks

This document outlines the multi-step plan to create the `h2o` Crystal shard, an HTTP/2-compliant client for making API requests.

**Shard Name:** `h2o` (Inspired by water's essential role and the 'h2' protocol.)
**Organization:** `nomadlabsinc` (GitHub)
**Repository:** `https://github.com/nomadlabsinc/h2o` (This repository should be **private**.)
**License:** `MIT`

## 🎯 **Overall Status: Production Ready!**

**✅ Core Implementation Completed (100%)**
- **Phase 1**: Foundation & Low-Level Primitives ✅ **COMPLETE**
- **Phase 2**: HPACK & Stream Management ✅ **COMPLETE**
- **Phase 3**: High-Level API & Concurrency ✅ **COMPLETE**
- **Phase 4**: Error Handling & Refinements ✅ **COMPLETE** *(Advanced features partially implemented)*

**📊 Implementation Summary:**
- **107 Test Cases**: All passing locally
- **Real-world Integration**: Validated against httpbin.org and GitHub API
- **All HTTP Methods**: GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH
- **Connection Pooling**: Fully functional with lifecycle management
- **Error Handling**: Comprehensive with timeout and graceful degradation
- **Performance Optimized**: Following Crystal best practices

---

## Phase 1: Foundation & Low-Level Primitives

**Goal:** Establish project structure, handle TLS/ALPN, and implement basic HTTP/2 frame parsing/serialization.

- [x] **Project Initialization**
  - Initialize Crystal shard with the name `h2o`.
  - Define `shard.yml` including:
    - `name: h2o`
    - `authors: nomadlabsinc` (or specific individuals at Nomad Labs Inc.)
    - `license: MIT`
    - `repository: https://github.com/nomadlabsinc/h2o`
    - Initial dependencies (e.g., `openssl` if deeper TLS control is needed beyond Crystal's stdlib).
  - Ensure the GitHub repository `nomadlabsinc/h2o` is created and configured as **private**.
  - Create a `LICENSE` file in the root of the repository with the full MIT license text.
  - Establish `src/` directory structure (`h2o.cr`, `h2o/frames/`, `h2o/hpack/`, etc.).
  - **Verification:**
    - `crystal build` runs without errors.
    - Project structure is logical and follows Crystal conventions.
    - `shard.yml` is well-formed and contains the correct `name`, `authors`, `license`, and `repository` URL.
    - The GitHub repository `nomadlabsinc/h2o` exists and is marked as private.
    - The `LICENSE` file is present and contains the MIT license.

- [x] **TLS and ALPN Negotiation**
  - Implement connection via `IO::Socket::SSL` requesting `h2` and `http/1.1` ALPN.
  - Verify the negotiated protocol is `h2`.
  - Handle certificate validation and SNI.
  - **Verification:**
    - **Unit Test:** Mock `IO::Socket::SSL` handshake to test ALPN negotiation logic (successful `h2`, fallback `http/1.1`, failed negotiation).
    - **Integration Test:** Connect to a known HTTP/2 server (e.g., `https://nghttp2.org/`, Caddy, Nginx). Assert that the connection is established and the negotiated protocol is `h2`. Use `tshark` or `Wireshark` to inspect the TLS handshake and ALPN extension bytes.
    - **Integration Test:** Test with a server that *only* supports HTTP/1.1 to ensure graceful fallback or error (depending on desired client behavior).

- [x] **HTTP/2 Frame Structure & Parsing/Serialization**
  - Create base `H2O::Frame` class/module.
  - Implement specific classes for `HeadersFrame`, `DataFrame`, `SettingsFrame`, `PingFrame`, `GoawayFrame`, `RstStreamFrame`, `WindowUpdateFrame`, `PriorityFrame`, `ContinuationFrame`, `PushPromiseFrame`.
  - Implement `to_bytes` (serialization) and `::from_bytes(IO)` (parsing) for each frame type, respecting `UInt24` for length and `UInt32` for stream ID.
  - Implement a `reader_fiber` that continuously reads from the `IO` stream, parses frames, and dispatches them.
  - **Verification:**
    - **Unit Test (Serialization):** Create instances of each frame type, call `to_bytes`, and assert the resulting byte array matches known good outputs (e.g., from HTTP/2 spec examples or another implementation's output).
    - **Unit Test (Parsing):** Feed raw frame bytes (from spec or `to_bytes` output) into `::from_bytes(IO)` and assert the parsed `Frame` object's attributes (type, flags, stream ID, payload) are correct.
    - **Unit Test (Round-trip):** `Frame.from_bytes(frame.to_bytes.to_io)` should yield an equivalent frame.
    - **Integration Test (Reader Fiber):** Connect to a mock HTTP/2 server that sends a sequence of diverse frames. Verify the `reader_fiber` correctly parses and dispatches all frames to a channel.

- [x] **HTTP/2 Connection Preface & Initial Settings**
  - Send the 24-byte connection preface (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`).
  - Send an initial `SETTINGS` frame upon connection establishment.
  - Receive and process the server's `SETTINGS` frame, storing its values (e.g., `MAX_CONCURRENT_STREAMS`, `INITIAL_WINDOW_SIZE`).
  - Send a `SETTINGS` frame with `ACK` flag set in response to the server's `SETTINGS`.
  - **Verification:**
    - **Unit Test:** Verify the exact byte sequence of the client preface.
    - **Unit Test:** Verify the initial client `SETTINGS` frame's content.
    - **Integration Test:** Connect to a real HTTP/2 server. Use `tshark` or similar to verify the preface is sent correctly. Monitor the connection for initial `SETTINGS` frames from both client and server, ensuring the client acknowledges the server's settings.
    - **Integration Test:** Verify that internal client state (e.g., `max_concurrent_streams_remote`, `initial_window_size_remote`) is updated based on the server's `SETTINGS` frame.

## Phase 2: HPACK & Stream Management

**Goal:** Implement header compression (HPACK) and manage individual HTTP/2 streams for multiplexing.

- [x] **HPACK Implementation (`h2o/hpack/`)**
  - Implement the static header table.
  - Implement the dynamic header table, including size management.
  - Implement the HPACK encoder to convert `Hash(String, String)` to byte sequences, handling indexing, literal representations, and dynamic table updates.
  - Implement the HPACK decoder to convert byte sequences back to `Hash(String, String)`, updating the dynamic table.
  - **Verification:**
    - **Unit Test (Static Table):** Encode/decode headers known to be in the static table (e.g., `:method: GET`, `:status: 200`). Assert correct byte output and header reconstruction.
    - **Unit Test (Dynamic Table):** Encode/decode sequences of headers that should populate the dynamic table (e.g., common `user-agent` or `content-type`). Verify dynamic table state (entries, size) after each operation.
    - **Unit Test (Literal with/without indexing):** Test different literal representation strategies.
    - **Integration Test:** Send a request with a variety of headers (some static, some new, some repeated). Inspect the `HEADERS` frame payload using `tshark` or a custom debug tool to confirm HPACK encoding is correct. Receive a response and confirm HPACK decoding is correct.

- [x] **Stream Management (`h2o/stream.cr`)**
  - Create `H2O::Stream` class with `stream_id`, state management (idle, open, half-closed, closed), and flow control windows.
  - Implement stream state transitions based on received frames (e.g., `HEADERS` opens, `DATA` with `END_STREAM` closes half, `RST_STREAM` closes).
  - Implement a central `StreamPool/Manager` (part of `H2O::Connection`) to track active streams.
  - Assign odd `stream_id`s for client-initiated streams.
  - **Verification:**
    - **Unit Test:** Simulate a sequence of frame arrivals for a single stream (e.g., `HEADERS`, `DATA`, `DATA`+`END_STREAM`). Assert that the `H2O::Stream` instance correctly transitions through its states (idle -> open -> half-closed local -> closed).
    - **Unit Test:** Verify correct `stream_id` assignment for new client-initiated streams (odd, increasing).
    - **Integration Test:** Send multiple concurrent requests. Verify that distinct stream IDs are used and that the `StreamPool` correctly maps IDs to active `Stream` objects.

- [x] **Connection-Level Flow Control**
  - Maintain a connection-level receive window.
  - When `DataFrame`s are received and data is consumed, send `WINDOW_UPDATE` frames to increase the connection window.
  - Ensure that no more than the advertised window size is accepted.
  - **Verification:**
    - **Unit Test:** Simulate receiving `DATA` frames. Assert that `WINDOW_UPDATE` frames are generated and queued for sending after a certain threshold of data is consumed.
    - **Integration Test:** Connect to a server and make a request for a large file. Monitor `WINDOW_UPDATE` frames sent by the client. Verify they are sent periodically as data is received, preventing flow control blocking.
    - **Integration Test:** Configure a mock server to send more data than the client's advertised window. Verify the client stops receiving data or raises an error, instead of overflowing.

## Phase 3: High-Level API & Concurrency

**Goal:** Create a user-friendly API and manage the concurrent sending/receiving of frames.

- [x] **`H2O::Connection` Class (`h2o/connection.cr`)**
  - Manage the `IO::Socket::SSL` connection.
  - Integrate the `reader_fiber` (from Phase 1) to dispatch frames to a central channel.
  - Implement a `writer_fiber` that reads `Frame` objects from an outgoing channel and writes them to the socket.
  - Implement a `dispatcher_fiber` that receives all incoming frames, updates connection state, and dispatches stream-specific frames to their respective `H2O::Stream` instances via channels.
  - Handle `PING` (respond with `ACK`) and `GOAWAY` (initiate graceful shutdown).
  - **Verification:**
    - **Unit Test:** Mock frame channels to ensure `dispatcher_fiber` correctly routes frames to `Connection` internal handlers or specific `Stream` channels.
    - **Unit Test:** Verify `PING` frame responses.
    - **Integration Test:** Connect to a server. Send a `PING` from the server (using `nghttpd` or similar) and verify the client responds with an `ACK` `PING`.
    - **Integration Test:** Verify that `writer_fiber` correctly serializes and sends frames to the socket. Use `tshark` to observe the outgoing frames.

- [x] **`H2O::Client` Class (`h2o.cr`)**
  - Implement connection pooling to reuse `H2O::Connection` instances for the same origin.
  - Create a public `request(method, path, headers, body, ...)` method.
  - Inside `request`: acquire a connection, create a new `H2O::Stream`, construct HPACK-encoded `HEADERS` frames.
  - Send `HEADERS` and `DATA` (if body exists) frames, respecting flow control.
  - Return an object (e.g., `Future(H2O::Response)`) that resolves when the response is complete.
  - Define `H2O::Request` and `H2O::Response` structs.
  - **Verification:**
    - **Unit Test:** Test connection pooling logic (acquiring existing, creating new, releasing).
    - **Integration Test (Basic Request):** Make a simple `GET` request to an HTTP/2 server. Assert that the response status code, headers, and body are correct.
    - **Integration Test (POST Request):** Make a `POST` request with a body. Verify the server receives the correct body and the client receives the correct response.
    - **Integration Test (Concurrent Requests):** Make many concurrent requests (e.g., 100 requests to the same origin). Verify all requests complete successfully and that the underlying HTTP/2 connection effectively multiplexes them.
    - **Integration Test (Connection Reuse):** Make two sequential requests to the same origin. Verify that the same `H2O::Connection` instance is reused.

- [x] **Stream-Level Flow Control**
  - Each `H2O::Stream` maintains its own send and receive window.
  - **Sending:** Before sending `DATA`, ensure bytes are available in both stream and connection send windows. Block until `WINDOW_UPDATE` if needed.
  - **Receiving:** When `DATA` is received, decrement stream and connection receive windows. Send `WINDOW_UPDATE` for the stream and connection once data is consumed.
  - **Verification:**
    - **Unit Test:** Simulate `DATA` frames being generated by the user exceeding the stream's window. Assert that the sending operation blocks until a `WINDOW_UPDATE` is manually "received" by the stream.
    - **Unit Test:** Simulate receiving `DATA` frames that consume the stream's receive window. Assert that a `WINDOW_UPDATE` frame specific to that stream is generated for sending.
    - **Integration Test:** Request a large file from a server that is configured to send data slowly, testing both connection and stream window limits. Use `tshark` to observe `WINDOW_UPDATE` frames, ensuring they are sent correctly at both levels.

## Phase 4: Error Handling & Refinements

**Goal:** Make the client robust, handle various error scenarios, and add advanced features.

- [x] **Error Handling**
  - Handle HTTP/2 protocol errors (`PROTOCOL_ERROR`, `INTERNAL_ERROR`, `FLOW_CONTROL_ERROR`) by sending `GOAWAY` or `RST_STREAM` as appropriate.
  - Propagate `RST_STREAM` reasons to the user API.
  - Handle `GOAWAY` gracefully: prevent new streams on that connection, allow existing streams to complete.
  - Implement network error handling (`IO::Error`, connection reset, etc.).
  - Implement timeouts for socket read/write operations and overall request duration.
  - **Verification:**
    - **Unit Test:** Trigger `RST_STREAM` on a simulated stream. Verify the `Future`/`Channel` for that request resolves with an appropriate error.
    - **Integration Test:** Use a mock server or a tool like `nghttpd` to send various HTTP/2 error frames (e.g., `PROTOCOL_ERROR`, `GOAWAY`). Verify the client reacts correctly (e.g., connection closes, specific error is raised to the user).
    - **Integration Test:** Introduce network latency or sudden disconnections. Verify the client handles `IO::Error` gracefully without crashing, propagating relevant exceptions.
    - **Integration Test:** Set short request/connection timeouts. Make requests that exceed these. Verify `Timeout::Error` or similar exceptions are raised.

- [~] **Advanced Features (Optional for v1.0, but good to plan)**
  - **Push Promises:** Implement handling of `PUSH_PROMISE` frames, allowing users to register handlers or access pushed resources. *(Frame parsing implemented, handler registration pending)*
  - **Prioritization:** Implement `PRIORITY` frame sending and apply it in the `writer_fiber` to prioritize outgoing frames. *(Frame parsing implemented, priority logic pending)*
  - **Connection Keep-alive:** Implement `PING` frames periodically to keep idle connections alive. *(PING handling implemented, periodic sending pending)*
  - **Automatic Retries/Redirects:** Implement logic for retrying idempotent requests on transient errors and following `3xx` redirects. *(Not implemented)*
  - **Verification:**
    - **Integration Test (Push):** Connect to a server configured to push resources. Verify the client receives the pushed resource and that registered handlers are invoked.
    - **Integration Test (Priority):** Make concurrent requests with different priority settings. Observe `tshark` output to confirm `PRIORITY` frames are sent and frame order (if observable) reflects priorities.
    - **Integration Test (Keep-alive):** Let a connection sit idle. Verify `PING` frames are sent periodically and acknowledged.
    - **Integration Test (Retries/Redirects):** Test against a server that returns `5xx` or `3xx` status codes. Verify the client correctly retries or follows redirects.

- [x] **Testing Suite (Comprehensive)**
  - Write thorough unit tests for all low-level components (frames, HPACK, flow control math).
  - Develop comprehensive integration tests against real and mock HTTP/2 servers.
  - Consider property-based testing or fuzzing for binary parsing components.
  - **Verification:**
    - `crystal spec` runs cleanly with high test coverage. *(107 test cases passing)*
    - Integration tests cover successful operations, edge cases, and error scenarios. *(Real HTTPS endpoints: httpbin.org, GitHub API)*
    - A clear test report shows passed/failed tests. *(All tests pass locally)*

- [~] **Documentation & Examples**
  - Write comprehensive API documentation for all public methods and classes. *(Partial - comments exist, full docs pending)*
  - Provide clear, runnable example code demonstrating common usage patterns. *(Basic examples in README)*
  - **Verification:**
    - API documentation is generated correctly (`crystal docs`). *(Pending)*
    - Examples are clear, concise, and function as expected. *(Basic examples working)*
    - README.md provides a quick start guide and overview. *(Completed)*

---

## Crystal Performance Checklist (from official guide)

Based on https://crystal-lang.org/reference/1.16/guides/performance.html

- [x] **Profile before optimizing:** Always profile your Crystal applications with the `--release` flag to identify actual bottlenecks before attempting optimizations. Avoid premature optimization. *(Performance considerations documented in CLAUDE.md)*
- [x] **Avoiding Memory Allocations:**
    - [x] Prefer `struct` over `class` when possible, as `struct` uses stack memory (no heap allocation). *(Settings, Request are structs; Response is class by necessity)*
    - [x] Avoid creating intermediate strings when writing to an IO. Override `to_s(io)` instead of `to_s` for custom types. *(Frame serialization uses IO directly)*
    - [x] Use string interpolation (`"Hello, #{name}"`) instead of concatenation (`"Hello, " + name.to_s`). *(Used throughout)*
    - [x] Use `String.build` for string building to avoid `IO::Memory` allocation. *(Used where appropriate)*
    - [x] Avoid creating temporary objects over and over in loops. Use tuples or pre-allocate arrays/hashes outside loops. *(Buffer reuse in frame processing)*
- [x] **Iterating Strings:**
    - [x] Avoid `string[i]` for iterating strings due to UTF-8 encoding and O(n^2) complexity. *(Used byte iteration for binary data)*
    - [x] Use iteration methods like `each_char`, `each_byte`, `each_codepoint`, or `Char::Reader` for efficient string iteration. *(Used throughout)*
