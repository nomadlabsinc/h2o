package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("6.3/1", test6_3_1)
	verifier.Register("6.3/2", test6_3_2)
}

// Test Case 6.3/1: Sends a PRIORITY frame with 0x0 stream identifier.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test6_3_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "stream", "identifier")
}

// Test Case 6.3/2: Sends a PRIORITY frame with a length other than 5 octets.
// Expected: Client should detect FRAME_SIZE_ERROR.
func test6_3_2() error {
	return verifier.ExpectStreamError(http2.ErrCodeFrameSize)
}