package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.7/1", testGeneric3_7_1)
}

// Test Case generic/3.7/1: Sends a PING frame.
// Expected: Client should accept PING frame successfully.
func testGeneric3_7_1() error {
	return verifier.ExpectSuccessfulRequest()
}