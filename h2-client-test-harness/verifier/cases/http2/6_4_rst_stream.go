package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.4/1", test6_4_1)
	verifier.Register("6.4/2", test6_4_2)
	verifier.Register("6.4/3", test6_4_3)
}

// Test Case 6.4/1: Sends a RST_STREAM frame with 0x0 stream identifier.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_4_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "identifier")
}

// Test Case 6.4/2: Sends a RST_STREAM frame on a idle stream.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_4_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "idle", "stream")
}

// Test Case 6.4/3: Sends a RST_STREAM frame with a length other than 4 octets.
// Expected: Client should detect FRAME_SIZE_ERROR.
func test6_4_3() error {
	return verifier.ExpectConnectionError("FRAME_SIZE_ERROR", "length", "frame")
}