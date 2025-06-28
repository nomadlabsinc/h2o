package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.2/1", test6_2_1)
	verifier.Register("6.2/2", test6_2_2)
	verifier.Register("6.2/3", test6_2_3)
	verifier.Register("6.2/4", test6_2_4)
}

// Test Case 6.2/1: Sends a HEADERS frame without the END_HEADERS flag, and a PRIORITY frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_2_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "header", "continuation")
}

// Test Case 6.2/2: Sends a HEADERS frame to another stream while sending a HEADERS frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_2_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "header", "stream")
}

// Test Case 6.2/3: Sends a HEADERS frame with 0x0 stream identifier.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_2_3() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "identifier")
}

// Test Case 6.2/4: Sends a HEADERS frame with invalid pad length.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_2_4() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "padding", "frame")
}