package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("4.1/1", test4_1_1)
	verifier.Register("4.1/2", test4_1_2)
	verifier.Register("4.1/3", test4_1_3)
}

// Test Case 4.1/1: Sends a frame with unknown type.
// Expected: Client should ignore unknown frame and respond to subsequent PING.
func test4_1_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case 4.1/2: Sends a frame with undefined flag.
// Expected: Client should ignore undefined flags and process frame normally.
func test4_1_2() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case 4.1/3: Sends a frame with reserved field bit.
// Expected: Client should ignore reserved bit and process frame normally.
func test4_1_3() error {
	return verifier.ExpectSuccessfulRequest()
}