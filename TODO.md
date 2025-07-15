# TODO Plan for RFC 9113 Compliance

This document outlines the necessary steps to make the H2O HTTP/2 client fully compliant with RFC 9113.

## I. Connection Management

- [ ] **Connection Preface:** Verify that the client's connection preface is fully compliant with section 3.4 of RFC 9113.
- [ ] **SETTINGS Frame Handling:**
    - [ ] Review and ensure all required and optional settings are considered in the initial SETTINGS frame.
    - [ ] Ensure all defined settings in incoming SETTINGS frames are correctly processed.
    - [ ] Implement `SETTINGS_MAX_CONCURRENT_STREAMS` handling, respecting the limit when creating new streams.
    - [ ] Verify that SETTINGS frames are properly acknowledged.
- [ ] **Connection-Level Error Handling:**
    - [ ] Ensure `GOAWAY` frames are handled correctly, closing or stopping the creation of new streams.
    - [ ] Implement sending `GOAWAY` frames for connection-level errors on the client side.
- [ ] **PING and PONG Frames:**
    - [ ] Implement a mechanism to send `PING` frames to check connection health and measure RTT.

## II. Stream Management & Multiplexing

- [ ] **Full Multiplexing:** Refactor the client to support multiple concurrent requests and responses.
    - [ ] Introduce a `Stream` class to manage the state of each stream (e.g., `idle`, `open`, `half_closed_local`, `half_closed_remote`, `closed`).
    - [ ] Implement a stream management system to create, track, and destroy streams.
    - [ ] Make the `request` method asynchronous.
- [ ] **Stream States:**
    - [ ] Implement the full stream state machine as described in section 5.1 of RFC 9113.
    - [ ] Ensure that frames are only sent when the stream is in a valid state.
- [ ] **Flow Control:**
    - [ ] Implement stream-level flow control with its own flow control window for each stream.
    - [ ] Prevent sending `DATA` frames that exceed the connection or stream-level flow control window.
    - [ ] Send `WINDOW_UPDATE` frames to the server as data is consumed.
- [ ] **Stream Priority:**
    - [ ] Implement sending `PRIORITY` frames to suggest stream priorities.

## III. Frame Types

- [ ] **HEADERS Frame:**
    - [ ] Ensure the `END_STREAM` and `END_HEADERS` flags are set correctly.
- [ ] **DATA Frame:**
    - [ ] Ensure the `END_STREAM` flag is set correctly.
    - [ ] Implement sending `DATA` frames in chunks to respect flow control windows.
- [ ] **RST_STREAM Frame:**
    - [ ] Implement sending `RST_STREAM` frames when a stream needs to be cancelled.
- [ ] **CONTINUATION Frame:**
    - [ ] Implement logic to handle `HEADERS`, `PUSH_PROMISE`, and `CONTINUATION` frames as a single block.
- [ ] **PUSH_PROMISE Frame:**
    - [ ] Implement handling of `PUSH_PROMISE` frames, including creating "promised" streams or rejecting them.
- [ ] **WINDOW_UPDATE Frame:**
    - [ ] Handle incoming stream-level `WINDOW_UPDATE` frames.
    - [ ] Implement sending `WINDOW_UPDATE` frames.

## IV. HPACK

- [ ] **HPACK Compliance:**
    - [ ] Review the HPACK implementation in `src/h2o/hpack/` to ensure it's fully compliant with RFC 7541.
    - [ ] Verify dynamic table size updates are handled correctly.
    - [ ] Implement protection against HPACK-related attacks (e.g., "HPACK Bomb").

## V. Error Handling

- [ ] **Stream Errors:**
    - [ ] Send a `RST_STREAM` frame with the appropriate error code when a stream error occurs.
- [ ] **Connection Errors:**
    - [ ] Send a `GOAWAY` frame with the appropriate error code and the last-processed stream ID when a connection error occurs.

## VI. Security

- [ ] **TLS Requirements:**
    - [ ] Ensure the client uses TLS 1.2 or higher.
    - [ ] Verify the client uses a compliant set of cipher suites.
    - [ ] Verify the `TlsSocket` implementation uses Server Name Indication (SNI).
- [ ] **Denial of Service Mitigations:**
    - [ ] Review resource management to prevent DoS attacks.

## VII. Testing

- [ ] **Unit Tests:**
    - [ ] Add unit tests for all new and modified functionality.
- [ ] **Integration Tests:**
    - [ ] Create integration tests against a known-compliant HTTP/2 server.
    - [ ] Test concurrent requests, flow control, and other features.
- [ ] **Compliance Testing:**
    - [ ] Use `h2spec` to test the client's compliance and fix any reported issues.
