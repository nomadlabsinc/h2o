# RFC 9113 Compliance Specification and Test TODO for H2O Client

This document outlines a detailed plan for identifying and addressing potential areas where the H2O HTTP/2 client might lack compliance with RFC 9113, the current HTTP/2 specification. The focus is on differences and clarifications introduced by RFC 9113 compared to its predecessor, RFC 7540, as well as general areas requiring strict adherence.

## Key RFC 9113 Changes and Corresponding Test Areas

RFC 9113 refined and clarified several aspects of HTTP/2. Tests should specifically target these areas to ensure H2O's compliance.

### 1. Deprecation of `Upgrade: h2c` Mechanism (RFC 9113, Section 3.2)

*   **RFC 7540:** Explicitly supported the `Upgrade: h2c` mechanism for establishing unencrypted HTTP/2 connections over an existing HTTP/1.1 connection.
*   **RFC 9113:** Deprecates `Upgrade: h2c`, strongly favoring "prior knowledge" (where the client directly sends an HTTP/2 connection preface without an HTTP/1.1 upgrade handshake).

**Test Scenarios:**

*   **Test 1.1: Client Behavior with `Upgrade: h2c` (Negative Test)**
    *   **Setup:** A mock server that *only* supports HTTP/1.1 and responds to `Upgrade: h2c` requests by attempting to switch to HTTP/2.
    *   **Action:** H2O client attempts to connect to this server using an `Upgrade: h2c` header.
    *   **Expected H2O Behavior (RFC 9113 Compliant):**
        *   The client should ideally *not* send the `Upgrade` header if it's configured for strict RFC 9113 compliance.
        *   If it does send the `Upgrade` header, it should treat the server's `101 Switching Protocols` response as an error or fall back to HTTP/1.1, rather than proceeding with HTTP/2 over the upgraded connection.
        *   The client should log a warning or error indicating the deprecated mechanism.
    *   **Rationale:** This test verifies if H2O actively avoids or correctly handles the deprecated `Upgrade` mechanism, distinguishing it from RFC 7540 behavior.

*   **Test 1.2: Client Behavior with "Prior Knowledge" h2c (Positive Test)**
    *   **Setup:** A mock HTTP/2 server that *only* supports "prior knowledge" h2c (i.e., it expects an HTTP/2 connection preface directly without any HTTP/1.1 handshake).
    *   **Action:** H2O client attempts to connect to this server without sending an `Upgrade` header, directly sending the HTTP/2 connection preface.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client successfully establishes an HTTP/2 connection and performs requests.
    *   **Rationale:** This confirms H2O's ability to use the preferred "prior knowledge" method for unencrypted HTTP/2.

### 2. `Content-Length` Header Field Semantics with Empty Bodies (RFC 9113, Section 8.1.2.6)

*   **RFC 9113 Clarification:** A `Content-Length` header field in a `HEADERS` frame that is followed by an `END_STREAM` flag and no `DATA` frames *must* indicate a length of 0. If it indicates a non-zero length, it's a `PROTOCOL_ERROR`.

**Test Scenarios:**

*   **Test 2.1: Non-Zero `Content-Length` with `END_STREAM` and No Data (Negative Test)**
    *   **Setup:** A mock HTTP/2 server sends a `HEADERS` frame with:
        *   `END_STREAM` flag set.
        *   A `Content-Length` header with a non-zero value (e.g., `Content-Length: 10`).
        *   *No* subsequent `DATA` frames.
    *   **Action:** H2O client receives this sequence.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client *must* generate a `PROTOCOL_ERROR` (error code 1) and terminate the stream or connection.
    *   **Rationale:** This directly tests adherence to a specific, explicit `PROTOCOL_ERROR` condition defined in RFC 9113.

*   **Test 2.2: Zero `Content-Length` with `END_STREAM` and No Data (Positive Test)**
    *   **Setup:** A mock HTTP/2 server sends a `HEADERS` frame with:
        *   `END_STREAM` flag set.
        *   A `Content-Length` header with a zero value (e.g., `Content-Length: 0`).
        *   *No* subsequent `DATA` frames.
    *   **Action:** H2O client receives this sequence.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client processes the request successfully without error.
    *   **Rationale:** Confirms correct handling of valid empty body scenarios.

### 3. Stream Prioritization (RFC 9113, Section 5.3)

*   **RFC 9113 Clarification:** While the core mechanism remains, RFC 9113 provides clearer guidance on how prioritization signals should be interpreted and applied.

**Test Scenarios:**

*   **Test 3.1: Client-Initiated Prioritization (Positive Test)**
    *   **Setup:** A mock HTTP/2 server that can observe the order of `DATA` frames or `HEADERS` frames from the client.
    *   **Action:** H2O client sends multiple concurrent requests with varying priority settings (dependencies and weights).
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client sends `PRIORITY` frames correctly and, if applicable, prioritizes its own outgoing `DATA` frames based on the specified weights and dependencies.
    *   **Rationale:** Verifies H2O's ability to signal its own prioritization preferences.

*   **Test 3.2: Server-Initiated Prioritization (Positive Test)**
    *   **Setup:** A mock HTTP/2 server sends `PRIORITY` frames to the client, instructing it to re-prioritize its active streams.
    *   **Action:** H2O client receives these `PRIORITY` frames.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client adjusts its internal processing or sending order of `DATA` frames for affected streams according to the server's prioritization signals.
    *   **Rationale:** Verifies H2O's ability to react to server-side prioritization.

### 4. Error Code Semantics and Handling (RFC 9113, Section 7)

*   **RFC 9113 Clarification:** While error codes are largely consistent, RFC 9113 might have subtle clarifications on when specific error codes *must* be generated or how they should be handled.

**Test Scenarios:**

*   **Test 4.1: Specific Error Code Generation (Negative Test)**
    *   **Setup:** A mock server induces a specific protocol violation that, according to RFC 9113, *must* result in a particular error code (e.g., `FRAME_SIZE_ERROR` for an oversized frame, `COMPRESSION_ERROR` for HPACK issues).
    *   **Action:** H2O client encounters this violation.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client generates the precise `GOAWAY` or `RST_STREAM` frame with the mandated error code.
    *   **Rationale:** Ensures H2O's error reporting is in strict compliance.

*   **Test 4.2: Handling of New/Clarified Error Conditions (Negative Test)**
    *   **Setup:** A mock server sends `GOAWAY` or `RST_STREAM` frames with error codes whose semantics might have been clarified or subtly changed in RFC 9113.
    *   **Action:** H2O client receives these error frames.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client reacts appropriately to the error, terminating streams/connections as required, and logging relevant information.
    *   **Rationale:** Verifies correct interpretation of error signals.

### 5. Connection Preface (RFC 9113, Section 3.4)

*   **RFC 9113 Clarification:** Confirms the exact byte sequence for the client connection preface.

**Test Scenarios:**

*   **Test 5.1: Correct Client Connection Preface (Positive Test)**
    *   **Setup:** A mock server that expects the exact HTTP/2 client connection preface.
    *   **Action:** H2O client initiates a connection.
    *   **Expected H2O Behavior (RFC 9113 Compliant):** The client sends the precise 24-octet connection preface string (`PRI * HTTP/2.0

SM

`) followed by a `SETTINGS` frame.
    *   **Rationale:** Basic but critical compliance check.

## General RFC 9113 Compliance Areas (Reinforcement)

Beyond the specific changes, a truly compliant client must rigorously adhere to the entire specification. These areas should be continuously tested.

*   **Frame Format Validation:**
    *   Strict validation of all frame fields (length, type, flags, stream ID).
    *   Handling of reserved bits (R) and mandatory flags.
    *   Correct behavior on receiving frames with invalid lengths or malformed payloads.
*   **HPACK Conformance:**
    *   Full implementation of HPACK (RFC 7541, referenced by RFC 9113) for header compression and decompression.
    *   Correct dynamic table management (insertion, eviction, size limits).
    *   Robust handling of Huffman encoding/decoding.
    *   Error handling for `COMPRESSION_ERROR`.
*   **Flow Control:**
    *   Accurate connection and stream-level window management.
    *   Correct generation and processing of `WINDOW_UPDATE` frames.
    *   Proper pausing/resuming of data transmission based on window availability.
    *   Error handling for `FLOW_CONTROL_ERROR`.
*   **Stream State Machine:**
    *   Correct transitions between all stream states (idle, reserved, open, half-closed, closed).
    *   Proper handling of frames in invalid states, leading to `PROTOCOL_ERROR` or `STREAM_CLOSED`.

## Feasibility of `h2spec` Compliance Tests in a `rfc_9113` Folder

It is **not possible** to directly "add" `h2spec` compliance tests into a `rfc_9113` folder within the H2O codebase in the same way one would add unit tests. `h2spec` is an external, standalone conformance test suite that runs *against* an HTTP/2 implementation (like H2O). It acts as a separate client/server that interacts with the implementation under test.

However, it is **highly recommended and entirely feasible** to create an `rfc_9113` folder (e.g., `spec/compliance/rfc_9113/`) that serves as a dedicated location for:

1.  **`h2spec` Integration Documentation:**
    *   Instructions on how to run H2O against `h2spec`.
    *   Configuration files for `h2spec` specific to H2O.
    *   Scripts to automate `h2spec` runs (e.g., a shell script that starts H2O, runs `h2spec` against it, and captures results).
    *   Parsed `h2spec` results, especially highlighting any failures or areas of non-compliance.

2.  **Custom RFC 9113-Specific Integration Tests:**
    *   This folder can contain new integration tests written in Crystal (or whatever language H2O's tests are in) that specifically target the RFC 9113 nuances outlined above (e.g., `Upgrade: h2c` deprecation, `Content-Length` semantics).
    *   These tests would likely use a mock HTTP/2 server (as described in the "Test Scenarios" sections) to precisely control the incoming frames and observe H2O's reactions.

3.  **Test Helpers and Utilities:**
    *   Any Crystal code that helps in setting up RFC 9113-specific mock servers, generating specific frame sequences, or asserting complex protocol behaviors.

**Proposed Folder Structure:**

```
/Users/robcole/dev/h2o/
└───spec/
    └───compliance/
        ├───rfc_9113/
        │   ├───README.md                 // Explains the purpose of this folder
        │   ├───h2spec_integration.sh     // Script to run h2spec against H2O
        │   ├───h2spec_results_latest.json // Latest h2spec results
        │   ├───h2spec_config.yml         // h2spec configuration for H2O
        │   ├───h2c_deprecation_spec.cr   // Test for Upgrade: h2c deprecation
        │   ├───content_length_spec.cr    // Test for Content-Length semantics
        │   ├───prioritization_spec.cr    // Tests for stream prioritization
        │   └───error_handling_spec.cr    // Tests for specific error code handling
        └───... (other compliance tests)
```

By adopting this approach, the H2O project can clearly delineate its RFC 9113 compliance efforts, track progress, and ensure that future changes are tested against the latest specification.
