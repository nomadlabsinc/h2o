package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.2/1", testGeneric3_2_1)
	verifier.Register("generic/3.2/2", testGeneric3_2_2)
	verifier.Register("generic/3.2/3", testGeneric3_2_3)
}

// Test Case generic/3.2/1: Sends a HEADERS frame.
// Expected: Client should accept HEADERS frame successfully.
func testGeneric3_2_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.2/2: Sends a HEADERS frame with padding.
// Expected: Client should accept HEADERS frame with padding successfully.
func testGeneric3_2_2() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.2/3: Sends a HEADERS frame with priority.
// Expected: Client should accept HEADERS frame with priority successfully.
func testGeneric3_2_3() error {
	return verifier.ExpectSuccessfulRequest()
}