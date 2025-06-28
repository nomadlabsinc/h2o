package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.8/1", testGeneric3_8_1)
}

// Test Case generic/3.8/1: Sends a GOAWAY frame.
// Expected: Client should accept GOAWAY frame successfully.
func testGeneric3_8_1() error {
	return verifier.ExpectSuccessfulRequest()
}