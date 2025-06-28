package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("5.1.1/1", test5_1_1_1)
	verifier.Register("5.1.1/2", test5_1_1_2)
}

// Test Case 5.1.1/1: Sends even-numbered stream identifier.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_1_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "identifier")
}

// Test Case 5.1.1/2: Sends stream identifier that is numerically smaller than previous.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_1_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "order")
}