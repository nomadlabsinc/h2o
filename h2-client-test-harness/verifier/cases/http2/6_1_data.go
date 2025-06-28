package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("6.1/1", test6_1_1)
	verifier.Register("6.1/2", test6_1_2)
	verifier.Register("6.1/3", test6_1_3)
}

// Test Case 6.1/1: Sends a DATA frame with 0x0 stream identifier.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_1_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "connection")
}

// Test Case 6.1/2: Sends a DATA frame on the stream that is not in "open" or "half-closed (local)" state.
// Expected: Client should detect STREAM_CLOSED error.
func test6_1_2() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 6.1/3: Sends a DATA frame with invalid pad length.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_1_3() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "padding", "frame")
}