# Refactor Plan: Separating Concerns in H2O HTTP/2 Client

This document outlines a detailed refactoring plan for the `h2o` HTTP/2 client, aiming to improve separation of concerns (Single Responsibility Principle - SRP), enhance testability and maintainability, and lay a solid foundation for future RFC9113 compliance and advanced features like true multiplexing. The proposed architecture draws inspiration from robust HTTP/2 implementations like Hyper in Rust, emphasizing distinct layers of responsibility.

## Current Architecture Overview and Identified Issues

The current `h2o` client, particularly `H2O::Client` and `H2O::H2::Client`, exhibits a monolithic design where multiple responsibilities are intertwined.

**Key Observations:**

*   **`H2O::Client`:** Acts as a high-level entry point, but also manages connection pooling, protocol fallback (HTTP/1.1 vs. HTTP/2), and circuit breaking. This mixes application-level concerns with connection management.
*   **`H2O::H2::Client`:** This is the core HTTP/2 implementation, but it directly handles:
    *   TCP/TLS socket management.
    *   HTTP/2 connection preface and settings.
    *   HPACK encoding/decoding.
    *   Connection-level flow control.
    *   Simplified stream management (currently single request per connection).
    *   Direct frame reading/writing.
    This tight coupling makes it difficult to test individual components in isolation and to evolve the protocol logic.
*   **I/O and Framing:** The `Frame` class directly reads from `IO`, and `H2::Client` directly writes frames. This couples framing logic with the underlying I/O. The `IOOptimizer` exists but is currently disabled due to "socket state conflicts," indicating a deeper issue with I/O management.
*   **Stream Management:** While `Stream` and `StreamPool` classes exist, `StreamPool` is not fully utilized for multiplexing in `H2::H2::Client`. Object pooling for streams and frames is explicitly disabled due to "memory corruption" issues, which is a critical concern for stability and performance.
*   **Global State:** The use of global singletons for `BufferPool`, `StringPool`, and `TLSCache` (though some are currently disabled) introduces shared mutable state, making concurrency management complex and contributing to the "memory corruption" issues.
*   **Validation Logic:** Validation modules are well-defined but their integration points within the monolithic `H2::Client` could be more explicit and layered.

## Proposed Layered Architecture

To address these issues, we propose a layered architecture with clear responsibilities for each component.

```
+-----------------------------------+
| Layer 7: Client API               |
| (H2O::HttpClient, ConnectionPool,     |
|  ProtocolNegotiator, CircuitBreakerManager) |
+-----------------------------------+
| Layer 6: HTTP Semantics           |
| (RequestTranslator, ResponseTranslator) |
+-----------------------------------+
| Layer 5: Stream Management        |
| (Stream, StreamPool, StreamFlowControl, StreamPrioritizer) |
+-----------------------------------+
| Layer 4: Connection Management    |
| (H2Connection, ConnectionSettings, ConnectionFlowControl) |
+-----------------------------------+
| Layer 3: HPACK                    |
| (HPACK::Encoder, HPACK::Decoder,  |
|  DynamicTable, StaticTable, Huffman) |
+-----------------------------------+
| Layer 2: Framing                  |
| (FrameReader, FrameWriter, Frame subclasses, FrameValidation) |
+-----------------------------------+
| Layer 1: Transport                |
| (TcpSocket, TlsSocket)            |
+-----------------------------------+
```

### Layer 1: Transport (Socket Management)

**Responsibility:** Handles raw TCP/TLS connections, providing a reliable byte stream for higher layers.
**Current Classes:** `H2O::TcpSocket`, `H2O::TlsSocket`.
**Refactor Checklist:**

*   [ ] **`H2O::TcpSocket`:** Ensure it strictly focuses on TCP connection establishment and raw byte I/O.
*   [ ] **`H2O::TlsSocket`:** Ensure it strictly focuses on TLS handshake, ALPN negotiation, and encrypted byte I/O over a `TcpSocket`. It should *not* contain HTTP/2 specific logic beyond ALPN.
*   [ ] **Error Handling:** Standardize error propagation for network-related issues (e.g., `ConnectionError`, `IO::TimeoutError`).

**Reasoning for Improvement:**
This layer provides a clean abstraction over network communication. By separating it, we can easily swap out underlying transport mechanisms (e.g., QUIC in the future) without affecting higher layers. It also makes testing network connectivity and TLS negotiation in isolation straightforward.

### Layer 2: Framing (HTTP/2 Frame Protocol)

**Responsibility:** Encodes and decodes HTTP/2 frames from/to raw byte streams. Applies frame-level validation.
**Current Classes:** `H2O::Frame` (base class), `H2O::frames/*` (subclasses), `H2O::frames::FrameValidation`, `H2O::frames::FrameBatchProcessor`.
**Refactor Checklist:**

*   [ ] **`FrameReader` (New Class/Module):**
    *   Encapsulate `Frame.from_io` logic.
    *   Take an `IO` stream as input.
    *   Handle reading the 9-byte frame header and the payload.
    *   Integrate `FrameValidation.validate_frame_size` and `FrameValidation.validate_stream_id_for_frame_type` *before* payload reading.
    *   Manage buffer allocation for payloads (addressing "memory corruption" related to `BufferPool` if it's due to incorrect `Bytes` reuse). Consider per-reader buffers or direct allocation.
*   [ ] **`FrameWriter` (New Class/Module):**
    *   Encapsulate `Frame.to_bytes` logic.
    *   Take a `Frame` object and an `IO` stream.
    *   Handle writing the 9-byte header and the payload.
    *   Integrate `IOOptimizer::BatchedWriter` here, if re-enabled, to batch frame writes for efficiency.
*   [ ] **`H2O::frames::FrameBatchProcessor`:** Re-evaluate its role. If `FrameReader` and `FrameWriter` handle single frames, batching could be an optimization layer *on top* of these, or integrated within them if it's a core performance primitive.
*   [ ] **`H2O::frames::FrameValidation`:** Ensure all frame-specific validations are called by `FrameReader` after a frame is parsed.

**Reasoning for Improvement:**
This layer strictly defines the HTTP/2 wire protocol. Decoupling frame parsing/serialization from connection management makes it highly testable. We can feed raw bytes to `FrameReader` and assert on the parsed `Frame` objects, or create `Frame` objects and assert on the bytes produced by `FrameWriter`. This is crucial for RFC compliance testing.

### Layer 3: HPACK (Header Compression)

**Responsibility:** Compresses and decompresses HTTP/2 headers using the HPACK algorithm.
**Current Classes:** `H2O::HPACK::Encoder`, `H2O::HPACK::Decoder`, `H2O::HPACK::DynamicTable`, `H2O::HPACK::StaticTable`, `H2O::HPACK::Huffman`, `H2O::HPACK::Presets`, `H2O::HPACK::StrictValidation`.
**Refactor Checklist:**

*   [ ] **`HPACK::Encoder` and `HPACK::Decoder`:** These classes are already well-separated. Ensure they are instantiated *per connection* (or per client if a client manages a single connection at a time) to manage their dynamic tables correctly.
*   [ ] **`HPACK::StrictValidation`:** Ensure `HPACK::Decoder` rigorously applies all strict validations during header decoding.
*   [ ] **`HpackSecurityLimits`:** This struct in `types.cr` should be passed explicitly to `HPACK::Decoder` and `HPACK::Encoder` during initialization, rather than relying on implicit defaults or global state.

**Reasoning for Improvement:**
HPACK is a stateful compression algorithm. By keeping its components isolated and ensuring their state is managed per connection, we prevent cross-connection interference and simplify reasoning about header compression. This layer is already quite good, but its integration needs to be explicit.

### Layer 4: Connection Management (HTTP/2 Connection State)

**Responsibility:** Manages the HTTP/2 connection-level state, including the connection preface, SETTINGS frames, connection-level flow control, and GOAWAY frames. It acts as the central coordinator for all streams on a single HTTP/2 connection.
**Current Classes:** Partially in `H2O::H2::Client`.
**New/Refactored Classes:**

*   [ ] **`H2Connection` (New Core Class):**
    *   Takes a `TlsSocket` (or `TcpSocket` for prior knowledge) in its constructor.
    *   Owns an instance of `FrameReader` and `FrameWriter`.
    *   Owns an instance of `HPACK::Encoder` and `HPACK::Decoder`.
    *   Manages `local_settings` and `remote_settings`.
    *   Manages connection-level `connection_window_size`.
    *   Handles sending the connection preface and initial SETTINGS.
    *   Handles receiving and processing connection-level frames (SETTINGS, PING, GOAWAY, WINDOW_UPDATE for stream ID 0).
    *   Sends SETTINGS ACK and PING ACK.
    *   Manages the `StreamPool` (see Layer 5).
    *   Provides methods for sending frames (e.g., `send_frame(frame : Frame)` which uses `FrameWriter`).
    *   Provides methods for receiving frames (e.g., `receive_frame : Frame?` which uses `FrameReader`).
    *   Handles connection-level errors (e.g., `ConnectionError`).
    *   Manages the `closing` state and sending `GOAWAY`.
*   [ ] **`ConnectionSettings` (New Class/Struct):** Encapsulates `local_settings` and `remote_settings` from `H2::Client`.
*   [ ] **`ConnectionFlowControl` (New Class/Module):** Extracts connection-level flow control logic from `H2::Client` and `FlowControlValidation`. Manages the connection window and applies validation.

**Reasoning for Improvement:**
This is a crucial separation. `H2Connection` becomes the single source of truth for a given HTTP/2 connection's state. It orchestrates the lower-level framing and HPACK layers and interacts with the higher-level stream management. This makes the connection logic highly testable and allows for more complex connection-level behaviors (e.g., graceful shutdown, error handling) to be managed centrally.

### Layer 5: Stream Management (HTTP/2 Stream State & Multiplexing)

**Responsibility:** Manages the lifecycle, state, and flow control for individual HTTP/2 streams. Enables true multiplexing by coordinating multiple concurrent streams over a single `H2Connection`.
**Current Classes:** `H2O::Stream`, `H2O::StreamPool`.
**Refactor Checklist:**

*   [ ] **`H2O::Stream`:**
    *   Ensure it strictly manages its own state (`StreamState`), stream-level flow control (`local_window_size`, `remote_window_size`), and incoming/outgoing data.
    *   Its `receive_headers`, `receive_data`, `receive_rst_stream`, `receive_window_update` methods should update its internal state and flow control, and then notify the `H2Connection` or a dedicated stream handler.
    *   **Address "Memory Corruption" for Streams:** Remove any attempts at object pooling for `Stream` instances. Allocate new `Stream` objects as needed and rely on Crystal's GC. The `reset_for_reuse` and `can_be_pooled?` methods should be removed.
*   [ ] **`H2O::StreamPool`:**
    *   Owned by `H2Connection`.
    *   Manages the collection of active and closed streams.
    *   Handles `max_concurrent_streams` limit.
    *   Provides methods to create new streams (`create_stream`), retrieve streams (`get_stream`), and remove streams (`remove_stream`).
    *   Integrate `StreamRateLimitConfig` and `track_stream_reset` for rapid reset attack mitigation.
    *   Provides methods for iterating over streams (e.g., `prioritized_streams`, `streams_needing_window_update`).
    *   **Address "Memory Corruption" for StreamPool:** Ensure `StreamPool` does *not* attempt to pool `Stream` objects. Its role is to manage the *collection* of streams, not their lifecycle beyond creation/deletion.
*   [ ] **`StreamFlowControl` (New Class/Module):** Extracts stream-level flow control logic from `Stream` and `FlowControlValidation`. Manages the stream window and applies validation.
*   [ ] **`StreamPrioritizer` (New Class/Module):** Extracts priority logic from `Stream` and `ProtocolOptimizer`. Manages stream dependencies and weights.

**Reasoning for Improvement:**
This layer is critical for true HTTP/2 multiplexing. By centralizing stream management, `H2Connection` can efficiently dispatch incoming frames to the correct stream and prioritize outgoing frames. Removing problematic object pooling for streams will significantly improve stability and reliability.

### Layer 6: HTTP Semantics (Request/Response Abstraction)

**Responsibility:** Translates high-level HTTP requests (`H2O::Request`) into HTTP/2 frames (`HEADERS`, `DATA`) and reconstructs `H2O::Response` objects from received frames.
**Current Classes:** Partially in `H2O::H2::Client`'s `send_request` and `read_response` methods.
**New Classes:**

*   [ ] **`RequestTranslator` (New Class):**
    *   Takes an `H2O::Request` object.
    *   Uses `HPACK::Encoder` to encode headers.
    *   Generates `HeadersFrame` and `DataFrame` objects.
    *   Handles pseudo-header generation (`:method`, `:path`, `:scheme`, `:authority`).
*   [ ] **`ResponseTranslator` (New Class):**
    *   Takes a sequence of `HeadersFrame` and `DataFrame` objects for a given stream.
    *   Uses `HPACK::Decoder` to decode headers.
    *   Constructs an `H2O::Response` object.
    *   Handles `:status` pseudo-header extraction.

**Reasoning for Improvement:**
This layer decouples the generic HTTP request/response model from the specifics of HTTP/2 framing. This makes it easier to support different HTTP versions or to change HTTP/2 framing details without affecting the core client API. It also simplifies testing of request/response mapping.

### Layer 7: Client API (Public Interface)

**Responsibility:** Provides the public-facing, user-friendly API for making HTTP requests. Manages connection pooling, protocol negotiation, and integrates circuit breaking.
**Current Classes:** `H2O::Client`.
**Refactor Checklist:**

*   [ ] **`H2O::Client` (Refactored):**
    *   Its primary role becomes managing a pool of `H2Connection` instances (and potentially `H1::Client` instances for fallback).
    *   It should *not* directly handle socket I/O or frame parsing.
    *   It will use a `ConnectionPool` (new class) to acquire/release connections.
    *   It will use a `ProtocolNegotiator` (new class) to determine the preferred protocol (HTTP/1.1 or HTTP/2) for a given host.
    *   It will integrate `CircuitBreakerManager` (new class) to apply circuit breaking logic.
    *   The `request` method will orchestrate:
        1.  Protocol negotiation.
        2.  Acquiring a connection from the pool.
        3.  Using `RequestTranslator` to convert `H2O::Request` to frames.
        4.  Sending frames via the `H2Connection` (or `H1::Client`).
        5.  Using `ResponseTranslator` to convert received frames to `H2O::Response`.
        6.  Releasing the connection back to the pool.
*   [ ] **`ConnectionPool` (New Class):**
    *   Manages a pool of `H2Connection` (and `H1::Client`) instances.
    *   Handles connection lifecycle (creation, reuse, eviction based on health/idle time).
    *   Replaces the connection management logic currently in `H2O::Client`.
    *   **Address "Memory Corruption" for TLS Cache/String Pool:** `TLSCache` and `StringPool` should be instance variables of `ConnectionPool` or `H2O::Client`, ensuring their state is isolated per client instance, not global.
*   [ ] **`ProtocolNegotiator` (New Class):**
    *   Encapsulates the logic for determining if a host supports HTTP/2 (ALPN, prior knowledge).
    *   Uses `H2O::ProtocolCache` (which should be an instance variable, not global) to cache negotiation results.
    *   Handles the fallback logic to HTTP/1.1.
*   [ ] **`CircuitBreakerManager` (New Class):**
    *   Manages multiple `H2O::Breaker` instances (one per host/service).
    *   Provides a centralized way to apply circuit breaking to requests.
    *   `H2O::Breaker` instances should be created and managed by this class, not globally.
*   [ ] **`H2O::Configuration`:** Ensure this remains a simple, immutable configuration object that is passed down to relevant layers during initialization, rather than being accessed globally.

**Reasoning for Improvement:**
This refactoring creates a clean, stable, and extensible public API. Users interact with a high-level client that hides the complexities of connection management, protocol negotiation, and HTTP/2 internals. Each component (connection pool, protocol negotiator, circuit breaker) can be developed, tested, and maintained independently.

## Addressing "Memory Corruption" and Global State (Revisited)

The recurring "memory corruption" issues with object/string/TLS pooling are a major concern. The core problem likely stems from:

1.  **Global Mutable State:** Global singletons (`@@buffer_pool_stats`, `@@tls_cache`, `@@string_pool`, `@@frame_pool_manager`) are inherently difficult to manage in a concurrent environment, especially with Crystal's fibers. Fibers can switch contexts at any `select` or `IO` operation, leading to race conditions if shared mutable state is not *perfectly* synchronized.
2.  **Incorrect Object Reuse:** The `reset_for_reuse` methods being disabled suggests that objects were not being properly reset or that their internal state was being corrupted across reuses. This is a common pitfall with object pooling.

**Proposed Solutions:**

*   **Eliminate Global Singletons:**
    *   `H2O.config`: Should be passed explicitly to components that need it during initialization.
    *   `H2O.buffer_pool_stats`: Should be an instance property of `BufferPool` if stats are needed, or removed entirely if not critical for production.
    *   `H2O.tls_cache`: Should be an instance property of `ConnectionPool` or `H2O::Client`.
    *   `H2O.string_pool`: Should be an instance property of `H2Connection` or `HPACK::Encoder/Decoder` if string interning is truly beneficial and safe.
    *   `H2O.frame_pools`: Should be removed. Frames should be allocated on demand or managed by a per-connection `FramePool` if profiling indicates a bottleneck.
*   **Rethink Object Pooling:**
    *   **Frames and Streams:** For now, completely abandon object pooling for `Frame` and `Stream` objects. Allocate new instances for each use and let the garbage collector manage their memory. Modern GCs are highly optimized, and the overhead of allocation is often less than the complexity and bugs introduced by manual pooling. If profiling later reveals significant allocation bottlenecks, a *very carefully designed* per-fiber or per-connection pool with strict lifecycle management could be considered.
    *   **Buffers (`BufferPool`):** The `BufferPool` is a more common and potentially beneficial optimization. However, its current global nature and the "memory corruption" issues suggest it needs a thorough review.
        *   **Option A (Safer):** Make `BufferPool` an instance property of `H2Connection` or `FrameReader`/`FrameWriter`. This scopes the pool and reduces global contention.
        *   **Option B (Global, but safer):** If it must remain global, ensure *all* interactions are protected by a single, robust mutex, and that `Bytes` objects returned from the pool are truly independent and not subject to external modification while in use by other fibers. The current `Bytes.new(length) { |i| read_slice[i] }` approach in `Frame.from_io_with_buffer_pool` is a good step, as it copies data out of the pooled buffer, but the overall management needs scrutiny.
*   **Explicit Dependency Injection:** Instead of global accessors, pass dependencies (like `HPACK::Encoder`, `HPACK::Decoder`, `StreamPool`, `ConnectionSettings`) explicitly through constructors or method arguments. This makes the dependencies clear and facilitates testing with mocks or different implementations.

## Conclusion

This detailed refactoring plan aims to transform the `h2o` HTTP/2 client from a monolithic structure into a more modular, layered application. By strictly adhering to SRP, isolating state, and addressing the "memory corruption" issues by rethinking object/string/TLS pooling, the client will become significantly more testable, maintainable, and robust. This foundation will also make it much easier to implement advanced HTTP/2 features and ensure full RFC9113 compliance in the future.
