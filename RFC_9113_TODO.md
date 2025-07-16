# RFC 9113 Compliance: H2O Client Refactoring and Test Action Plan

This document outlines a detailed action plan to refactor the H2O HTTP/2 client, separating its core protocol logic from the underlying I/O mechanisms. This architectural change will significantly enhance testability, allowing for precise, in-memory protocol compliance testing against RFC 9113, while maintaining robust integration tests against real HTTP/2 servers.

## Goal

Achieve 100% confidence in H2O client's RFC 9113 compliance by:
1.  Architecturally separating the HTTP/2 protocol engine from the I/O layer.
2.  Implementing comprehensive unit/protocol tests using mock in-memory I/O.
3.  Maintaining and enhancing integration tests against real and specialized mock HTTP/2 servers.

## Phase 1: Architectural Refactoring (Core Separation)

**Objective:** Establish a clear boundary between protocol logic and I/O, enabling interchangeable transport mechanisms.

### Task 1.1: Define I/O Abstraction (Interface/Trait)
*   **Description:** Create a Crystal interface or abstract class that defines the contract for reading and writing raw bytes. This will be the `IoAdapter` or `Transport` interface.
*   **Methods (Example):**
    *   `read_bytes(buffer_size : Int) : Bytes | Nil` (non-blocking read, returns `nil` if no data available immediately)
    *   `write_bytes(bytes : Bytes) : Int` (writes bytes, returns number of bytes written)
    *   `close() : Nil`
    *   `on_data_available(&block : Bytes -> Nil) : Nil` (callback for asynchronous data arrival)
    *   `on_closed(&block : Nil -> Nil) : Nil` (callback for connection closure)
*   **Deliverable:** `src/h2o/io_adapter.cr` (or similar).

### Task 1.2: Encapsulate Protocol Engine
*   **Description:** Identify and extract all logic related to HTTP/2 frame parsing, serialization, HPACK, stream state management, flow control, and error generation into a new, dedicated component (e.g., `H2o::ProtocolEngine`). This component will *only* interact with the `IoAdapter`.
*   **Dependencies:** The `ProtocolEngine` will take an instance of `IoAdapter` in its constructor.
*   **Responsibilities:**
    *   Receiving raw bytes from `IoAdapter` and parsing them into HTTP/2 frames.
    *   Processing incoming frames and updating internal state (stream states, connection state, flow control windows).
    *   Generating outgoing HTTP/2 frames based on client requests or protocol events.
    *   Serializing outgoing frames into raw bytes and sending them via `IoAdapter`.
    *   Managing HPACK encoder/decoder state.
    *   Implementing HTTP/2 flow control logic.
    *   Detecting and generating appropriate HTTP/2 error codes (`PROTOCOL_ERROR`, `FLOW_CONTROL_ERROR`, etc.).
*   **Deliverable:** `src/h2o/protocol_engine.cr` (or similar), with existing protocol logic moved into it.

### Task 1.3: Implement `NetworkTransport`
*   **Description:** Create a concrete implementation of the `IoAdapter` that uses actual TCP/TLS sockets for network communication.
*   **Responsibilities:**
    *   Establishing TCP/TLS connections.
    *   Reading from and writing to network sockets.
    *   Handling network-level errors (connection refused, timeouts, etc.).
    *   Integrating with H2O's existing `tcp_socket.cr` and `tls.cr` components.
*   **Deliverable:** `src/h2o/network_transport.cr` (or similar).

### Task 1.4: Implement `InMemoryTransport` (Mock I/O)
*   **Description:** Create a concrete implementation of the `IoAdapter` that uses in-memory buffers or channels to simulate byte streams. This will be the backbone of unit/protocol testing.
*   **Responsibilities:**
    *   Providing methods to programmatically inject incoming bytes into its internal buffer.
    *   Providing methods to retrieve outgoing bytes written by the `ProtocolEngine`.
    *   Simulating connection closure.
*   **Deliverable:** `spec/support/in_memory_transport.cr` (or similar).

### Task 1.5: Update High-Level Client API
*   **Description:** Modify the existing `H2o::Client` (or equivalent high-level API) to utilize the new `ProtocolEngine` and accept an `IoAdapter` instance.
*   **Impact:** The client will no longer directly manage sockets; it will delegate I/O operations to the injected `IoAdapter`.
*   **Deliverable:** Modified `src/h2o/client.cr`.

## Phase 2: Unit/Protocol Compliance Testing (Leveraging `InMemoryTransport`)

**Objective:** Write comprehensive, fast, and deterministic tests for the `ProtocolEngine`'s RFC 9113 compliance.

### Task 2.1: Migrate Existing Protocol-Level Unit Tests
*   **Description:** Review existing unit tests that touch HTTP/2 frame handling, HPACK, or stream states. Adapt them to use the `InMemoryTransport` to isolate the `ProtocolEngine`.
*   **Deliverable:** Refactored existing tests.

### Task 2.2: Implement RFC 9113 Specific Unit Tests
*   **Description:** Create new test files within `spec/compliance/rfc_9113/` (as outlined in `RFC_9113_SPEC.md`) that specifically target RFC 9113 nuances using the `InMemoryTransport`.
*   **Test Categories:**
    *   **Frame Parsing/Serialization:**
        *   Test all 10 frame types with valid and invalid lengths, flags, and stream IDs.
        *   Verify correct handling of reserved bits (R) and mandatory flags.
        *   Assert `PROTOCOL_ERROR` or `FRAME_SIZE_ERROR` on malformed frames.
    *   **HPACK Conformance:**
        *   Comprehensive tests for static and dynamic table indexing, literal representation, and Huffman encoding/decoding.
        *   Test dynamic table size limits and eviction.
        *   Assert `COMPRESSION_ERROR` on invalid HPACK blocks.
    *   **Stream State Machine:**
        *   Drive the `ProtocolEngine` through all stream state transitions (idle, reserved, open, half-closed, closed) by injecting specific frame sequences.
        *   Assert correct state changes and `PROTOCOL_ERROR` or `STREAM_CLOSED` when frames are received in invalid states.
    *   **Flow Control:**
        *   Test connection and stream-level window management: decrementing on `DATA` sent, incrementing on `WINDOW_UPDATE`.
        *   Verify client pauses data transmission when window is exhausted.
        *   Assert `FLOW_CONTROL_ERROR` on invalid `WINDOW_UPDATE` increments or window overflows.
    *   **Error Generation and Handling:**
        *   Induce specific protocol violations (e.g., invalid `Content-Length` with `END_STREAM`) and assert that the `ProtocolEngine` generates the correct `GOAWAY` or `RST_STREAM` frame with the mandated error code.
        *   Test client's reaction to receiving `GOAWAY` and `RST_STREAM` frames with various error codes.
    *   **RFC 9113 Nuances (Specific Tests):**
        *   **`Upgrade: h2c` Deprecation:** Test that the client *does not* attempt to use `Upgrade: h2c` or correctly rejects/falls back if a server attempts to upgrade using this deprecated method. Focus on the client's *initiation* behavior.
        *   **`Content-Length` Semantics (RFC 9113, Section 8.1.2.6):** Test that a `HEADERS` frame with `END_STREAM` and a non-zero `Content-Length` (without subsequent `DATA` frames) results in a `PROTOCOL_ERROR`.
        *   **Prioritization:** Test that the client correctly sends `PRIORITY` frames and, if applicable, internally prioritizes its outgoing data based on received `PRIORITY` frames.
        *   **Connection Preface (RFC 9113, Section 3.4):** Verify the exact 24-octet client connection preface is sent.
*   **Deliverable:** New `.cr` test files in `spec/compliance/rfc_9113/`.

### Task 2.3: Integrate Fuzz Testing
*   **Description:** Implement fuzzing targets for the `ProtocolEngine` using the `InMemoryTransport` to feed it arbitrary or malformed byte streams.
*   **Tools:** Investigate Crystal fuzzing tools or adapt existing techniques (e.g., AFL, libFuzzer) to work with Crystal and the `InMemoryTransport`.
*   **Targets:** Focus fuzzing on frame parsing, HPACK decoding, and state machine transitions.
*   **Deliverable:** Fuzzing setup and initial fuzzing test cases.

## Phase 3: Integration Testing (Against Real/Mock Servers)

**Objective:** Verify end-to-end client behavior and interoperability with various HTTP/2 server implementations.

### Task 3.1: Review and Enhance Existing Integration Tests
*   **Description:** Ensure all existing integration tests (e.g., in `spec/integration/`) are still valid and robust with the new `NetworkTransport`.
*   **Enhancements:** Add more scenarios covering connection resilience, error recovery, and performance under realistic network conditions.
*   **Deliverable:** Updated `spec/integration/` tests.

### Task 3.2: Develop Custom Crystal Mock HTTP/2 Server for Advanced Scenarios
*   **Description:** Since `h2spec` is for servers and `h2specd` is for browsers, develop a lightweight, programmatic HTTP/2 server in Crystal that can be controlled by tests.
*   **Capabilities:** This server should be able to:
    *   Send specific, even malformed, HTTP/2 frames to the H2O client.
    *   Simulate various server behaviors (e.g., slow responses, unexpected `GOAWAY` frames, specific error codes).
    *   Observe and assert the frames sent by the H2O client.
*   **Integration:** This mock server would run as a separate process during integration tests, and H2O would connect to it via `NetworkTransport`.
*   **Deliverable:** `spec/support/mock_h2_server.cr` (or similar).

### Task 3.3: Interoperability Testing
*   **Description:** Set up a test matrix to run H2O against a variety of well-known HTTP/2 server implementations (e.g., Nginx with HTTP/2, Apache with `mod_http2`, Node.js `http2` module, Caddy, other language HTTP/2 server implementations).
*   **Scenarios:** Test basic requests, concurrent streams, large payloads, and error conditions across different server implementations.
*   **Deliverable:** Documentation of interoperability test setup and results.

## Phase 4: Continuous Integration and Reporting

**Objective:** Automate testing and provide clear, actionable compliance reports.

### Task 4.1: Automate Test Execution
*   **Description:** Integrate all new unit/protocol tests and enhanced integration tests into the project's CI/CD pipeline.
*   **Strategy:** Ensure tests run on every pull request or commit.
*   **Deliverable:** Updated CI configuration (e.g., `.github/workflows/ci.yml`).

### Task 4.2: Compliance Reporting
*   **Description:** Generate clear and concise test reports, specifically highlighting RFC 9113 compliance status.
*   **Tools:** Utilize Crystal's testing framework reporting capabilities, or integrate with external reporting tools if necessary.
*   **Content:** Reports should indicate which RFC 9113 sections are covered by tests and any failures related to compliance.
*   **Deliverable:** Automated test reports.

## Timeline (Estimated)

*   **Phase 1 (Refactoring):** 2-4 weeks
*   **Phase 2 (Unit/Protocol Tests):** 3-6 weeks
*   **Phase 3 (Integration Tests):** 2-4 weeks
*   **Phase 4 (CI/Reporting):** 1-2 weeks

**Total Estimated Time:** 8-16 weeks (highly dependent on current codebase complexity and team size).

## Success Metrics

*   All unit/protocol tests pass consistently.
*   All integration tests pass consistently.
*   No regressions introduced by refactoring.
*   Clear, actionable test reports indicating RFC 9113 compliance status.
*   Increased confidence in H2O's HTTP/2 client behavior.
