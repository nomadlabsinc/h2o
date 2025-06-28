package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("5.3.1/1", test5_3_1_1)
	verifier.Register("5.3.1/2", test5_3_1_2)
}

// Test Case 5.3.1/1: Sends HEADERS frame that depends on itself.
// Expected: Client should detect PROTOCOL_ERROR.
func test5_3_1_1() error {
	return verifier.ExpectStreamError(http2.ErrCodeProtocol)
}

// Test Case 5.3.1/2: Sends PRIORITY frame that depends on itself.
// Expected: Client should detect PROTOCOL_ERROR.
func test5_3_1_2() error {
	return verifier.ExpectStreamError(http2.ErrCodeProtocol)
}