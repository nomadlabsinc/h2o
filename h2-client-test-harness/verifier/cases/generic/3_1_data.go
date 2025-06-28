package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.1/1", testGeneric3_1_1)
	verifier.Register("generic/3.1/2", testGeneric3_1_2)
	verifier.Register("generic/3.1/3", testGeneric3_1_3)
}

// Test Case generic/3.1/1: Sends a DATA frame.
// Expected: Client should accept single DATA frame successfully.
func testGeneric3_1_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.1/2: Sends multiple DATA frames.
// Expected: Client should accept multiple DATA frames successfully.
func testGeneric3_1_2() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.1/3: Sends a DATA frame with padding.
// Expected: Client should accept DATA frame with padding successfully.
func testGeneric3_1_3() error {
	return verifier.ExpectSuccessfulRequest()
}