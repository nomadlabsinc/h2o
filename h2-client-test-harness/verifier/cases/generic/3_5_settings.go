package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.5/1", testGeneric3_5_1)
}

// Test Case generic/3.5/1: Sends a SETTINGS frame.
// Expected: Client should accept SETTINGS frame successfully.
func testGeneric3_5_1() error {
	return verifier.ExpectSuccessfulRequest()
}