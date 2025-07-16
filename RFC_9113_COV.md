# RFC 9113 HTTP/2 Client Test Coverage Review

This document summarizes observed testing strategies for HTTP/2 clients, with a focus on RFC 9113 compliance, drawing insights primarily from Go's `golang.org/x/net/http2` and Rust's `h2` and `hyper` crates.

## General Testing Approaches

### 1. Unit Testing
*   **Purpose:** Isolate and test individual components, functions, and state transitions.
*   **Key Aspects:**
    *   **Frame Parsing/Serialization:** Verifying correct encoding and decoding of all HTTP/2 frame types (DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PUSH_PROMISE, PING, GOAWAY, WINDOW_UPDATE, CONTINUATION) according to RFC 9113, Section 4.
    *   **HPACK Compression/Decompression:** Testing the correct implementation of HPACK (RFC 7541, now referenced by RFC 9113) for header field representation. This includes static and dynamic table management, Huffman encoding, and handling of various indexing and literal representation methods.
    *   **Stream State Management:** Ensuring the client correctly transitions between stream states (idle, reserved (local/remote), open, half-closed (local/remote), closed) as defined in RFC 9113, Section 5.1.
    *   **Flow Control Logic:** Testing the client's adherence to connection and stream-level flow control mechanisms (RFC 9113, Section 5.2), including window updates and handling of `FLOW_CONTROL_ERROR`.

### 2. Integration Testing
*   **Purpose:** Verify that different parts of the client work together correctly, often involving actual network communication.
*   **Key Aspects:**
    *   **Mock Servers:** Using mock HTTP/2 servers (e.g., Go's `httptest`, Rust's `httptest`, `mockito`) to simulate various server behaviors and responses. This allows for controlled testing of:
        *   **Successful Request/Response Cycles:** Basic end-to-end communication.
        *   **Error Handling:** Simulating various HTTP/2 errors (e.g., `PROTOCOL_ERROR`, `INTERNAL_ERROR`, `REFUSED_STREAM`, `CANCEL`, `COMPRESSION_ERROR`, `CONNECT_ERROR`, `ENHANCE_YOUR_CALM`, `INADEQUATE_SECURITY`, `HTTP_1_1_REQUIRED`) and ensuring the client reacts appropriately (RFC 9113, Section 5.4).
        *   **Edge Cases:** Testing unusual but valid scenarios, such as large headers, specific frame sequences, or flow control interactions.
        *   **Stream Multiplexing:** Verifying concurrent requests over a single connection.
        *   **Server Push:** Testing client handling of `PUSH_PROMISE` frames (RFC 9113, Section 6.6).
        *   **Connection Management:** Testing connection establishment, graceful shutdown (`GOAWAY`), and abrupt termination.
    *   **Real HTTP/2 Servers:** Testing against known, production-ready HTTP/2 servers (e.g., Nginx, Apache, or other compliant implementations) for interoperability and real-world performance.
    *   **TLS/ALPN:** Ensuring correct negotiation of HTTP/2 over TLS using ALPN.
    *   **H2C (HTTP/2 Cleartext):** Testing prior knowledge and (if supported) `Upgrade` mechanism, considering RFC 9113's deprecation of `Upgrade: h2c`.

### 3. Conformance Testing
*   **Purpose:** Strictly verify adherence to the HTTP/2 specification.
*   **Key Tool:**
    *   **`h2spec`:** A widely recognized conformance test suite for HTTP/2 implementations. Clients that pass `h2spec` demonstrate a high degree of RFC compliance. The strategy involves running the client against `h2spec` and ensuring all tests pass. This covers a vast array of protocol rules, including:
        *   Frame format validity.
        *   Correct handling of flags.
        *   Stream identifier usage.
        *   Settings parameters and their application.
        *   Error code generation and handling.
        *   HPACK encoding/decoding correctness.
        *   Flow control window management.
        *   Ping and GoAway behavior.

### 4. Fuzz Testing
*   **Purpose:** Uncover vulnerabilities and crashes by providing unexpected or malformed inputs.
*   **Key Aspects:**
    *   **Malformed Frames/Headers:** Sending invalid frame lengths, incorrect type/flags combinations, or corrupted header blocks.
    *   **Unexpected Data:** Introducing arbitrary data at unexpected points in the stream.
    *   **Protocol Violations:** Deliberately sending sequences of frames that violate the protocol state machine.

## RFC 9113 Specific Compliance Considerations

RFC 9113 updates RFC 7540. A truly compliant client must adhere to the nuances introduced or clarified in RFC 9113. This includes:

*   **Deprecation of `Upgrade: h2c`:** Clients should primarily use "prior knowledge" for unencrypted HTTP/2.
*   **Clarifications on `Content-Length`:** As seen in the Go example, specific details around header field semantics and their interaction with frame types are critical.
*   **Updated Error Codes and Semantics:** Ensuring correct use and interpretation of error codes.
*   **Stream Prioritization:** Adhering to the updated rules for stream prioritization.

## TODO: Strategies for 100% Confidence in RFC 9113 Compliance

To achieve 100% confidence in RFC 9113 compliance for an HTTP/2 client, the following strategies and tests are recommended:

1.  **Adopt/Integrate `h2spec` (or a similar comprehensive conformance suite):**
    *   **Priority:** High. This is the single most effective way to validate broad RFC compliance.
    *   **Action:** Run the client against the latest `h2spec` version that aligns with RFC 9113. If `h2spec` is not fully updated, contribute to its update or develop internal tests covering the RFC 9113 changes.
    *   **Strategy:** Automate `h2spec` runs in CI/CD pipelines.

2.  **Comprehensive Unit Tests for Frame Processing:**
    *   **Priority:** High.
    *   **Action:** Write unit tests for every HTTP/2 frame type (DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PUSH_PROMISE, PING, GOAWAY, WINDOW_UPDATE, CONTINUATION) to verify:
        *   Correct encoding and decoding of all fields (length, type, flags, R bit, stream ID, payload).
        *   Validation of reserved bits (R) and mandatory flags.
        *   Handling of invalid frame lengths or malformed payloads, leading to `PROTOCOL_ERROR` or `FRAME_SIZE_ERROR`.
        *   Correct application of flags (e.g., END_STREAM, END_HEADERS, ACK, PADDED).
    *   **Strategy:** Use byte-level manipulation to construct valid and invalid frames for testing.

3.  **Thorough HPACK Conformance Tests:**
    *   **Priority:** High.
    *   **Action:** Implement dedicated tests for HPACK encoder and decoder:
        *   **Static Table:** Verify correct indexing and lookup.
        *   **Dynamic Table:** Test insertion, eviction, and size management.
        *   **Huffman Encoding/Decoding:** Test all valid and invalid Huffman sequences.
        *   **Header Field Representation:** Test literal, indexed, and dynamic table updates for various header fields, including pseudo-headers.
        *   **Error Handling:** Test for `COMPRESSION_ERROR` on malformed HPACK blocks.
    *   **Strategy:** Use known HPACK test vectors (if available) or generate a comprehensive set of test cases.

4.  **Exhaustive Stream State Machine Tests:**
    *   **Priority:** High.
    *   **Action:** Create integration tests using mock servers to drive the client through all possible stream state transitions (RFC 9113, Section 5.1) and verify correct behavior and error generation (`PROTOCOL_ERROR`, `STREAM_CLOSED`).
    *   **Strategy:** For each state, send valid and invalid frames and assert the resulting state and any generated errors.

5.  **Robust Flow Control Tests:**
    *   **Priority:** High.
    *   **Action:** Implement tests for both connection and stream-level flow control:
        *   **Window Management:** Verify correct window size updates, decrementing on data sent, and incrementing on `WINDOW_UPDATE` frames.
        *   **Window Exhaustion:** Test client behavior when the window is exhausted (pausing data transmission).
        *   **Window Update Generation:** Ensure the client sends `WINDOW_UPDATE` frames correctly.
        *   **Invalid Window Updates:** Test handling of `WINDOW_UPDATE` frames that exceed maximum window size or have invalid increments, leading to `FLOW_CONTROL_ERROR`.
    *   **Strategy:** Use mock servers to control the flow control window and observe client behavior.

6.  **Comprehensive Error Handling Tests:**
    *   **Priority:** High.
    *   **Action:** Systematically test client reactions to all defined HTTP/2 error codes (RFC 9113, Section 7):
        *   `NO_ERROR`, `PROTOCOL_ERROR`, `INTERNAL_ERROR`, `FLOW_CONTROL_ERROR`, `SETTINGS_TIMEOUT`, `STREAM_CLOSED`, `FRAME_SIZE_ERROR`, `REFUSED_STREAM`, `CANCEL`, `COMPRESSION_ERROR`, `CONNECT_ERROR`, `ENHANCE_YOUR_CALM`, `INADEQUATE_SECURITY`, `HTTP_1_1_REQUIRED`.
        *   Verify correct connection/stream termination or error propagation.
    *   **Strategy:** Mock servers should send specific `GOAWAY` and `RST_STREAM` frames with various error codes.

7.  **Fuzz Testing for Robustness:**
    *   **Priority:** Medium-High.
    *   **Action:** Integrate fuzzing into the test suite, targeting:
        *   HTTP/2 frame parsing.
        *   HPACK decoding.
        *   Input streams (e.g., sending random bytes).
    *   **Strategy:** Use a fuzzing framework (e.g., `go-fuzz` for Go, `cargo-fuzz` for Rust) to generate malformed inputs.

8.  **Interoperability Testing:**
    *   **Priority:** Medium.
    *   **Action:** Test the client against a variety of other HTTP/2 server implementations (e.g., Nginx, Apache, Caddy, Node.js `http2` module, other language implementations).
    *   **Strategy:** Set up a test matrix with different server configurations (TLS, H2C, various settings).

9.  **Specific RFC 9113 Nuance Tests:**
    *   **Priority:** Medium.
    *   **Action:** Create targeted tests for specific changes or clarifications in RFC 9113 compared to RFC 7540, such as:
        *   Handling of `Content-Length` with empty bodies (as per the Go issue).
        *   Prior knowledge connection establishment for H2C.
        *   Updated prioritization rules.
    *   **Strategy:** Review RFC 9113 diffs from RFC 7540 and create specific test cases for each change.

10. **Performance and Resource Usage Tests:**
    *   **Priority:** Medium.
    *   **Action:** Implement benchmarks and load tests to ensure the client performs efficiently and manages resources correctly under various loads.
    *   **Strategy:** Measure throughput, latency, CPU, and memory usage.
