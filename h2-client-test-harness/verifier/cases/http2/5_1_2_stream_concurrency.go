package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("5.1.2/1", test5_1_2_1)
}

// Test Case 5.1.2/1: Sends HEADERS frames that causes their advertised concurrent stream limit to be exceeded.
// Expected: Client should detect PROTOCOL_ERROR or REFUSED_STREAM.
func test5_1_2_1() error {
	// Try for REFUSED_STREAM first, fall back to PROTOCOL_ERROR
	err := verifier.ExpectStreamError(http2.ErrCodeRefusedStream)
	if err == nil {
		return nil
	}
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "concurrent", "stream")
}