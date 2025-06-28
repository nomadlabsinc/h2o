package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("5.4.1/1", test5_4_1_1)
	verifier.Register("5.4.1/2", test5_4_1_2)
}

// Test Case 5.4.1/1: Sends an invalid PING frame for connection close.
// Expected: Client should close the TCP connection.
func test5_4_1_1() error {
	return verifier.ExpectConnectionError("FRAME_SIZE_ERROR", "ping", "length")
}

// Test Case 5.4.1/2: Sends an invalid PING frame to receive GOAWAY frame.
// Expected: Client should send GOAWAY frame.
func test5_4_1_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "ping", "stream")
}