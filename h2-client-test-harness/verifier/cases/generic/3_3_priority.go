package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.3/1", testGeneric3_3_1)
	verifier.Register("generic/3.3/2", testGeneric3_3_2)
	verifier.Register("generic/3.3/3", testGeneric3_3_3)
	verifier.Register("generic/3.3/4", testGeneric3_3_4)
	verifier.Register("generic/3.3/5", testGeneric3_3_5)
}

// Test Case generic/3.3/1: Sends a PRIORITY frame with priority 1.
// Expected: Client should accept PRIORITY frame successfully.
func testGeneric3_3_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.3/2: Sends a PRIORITY frame with priority 256.
// Expected: Client should accept PRIORITY frame successfully.
func testGeneric3_3_2() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.3/3: Sends a PRIORITY frame with stream dependency.
// Expected: Client should accept PRIORITY frame successfully.
func testGeneric3_3_3() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.3/4: Sends a PRIORITY frame with exclusive.
// Expected: Client should accept PRIORITY frame successfully.
func testGeneric3_3_4() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.3/5: Sends a PRIORITY frame for an idle stream, then send a HEADERS frame.
// Expected: Client should respond to HEADERS frame successfully.
func testGeneric3_3_5() error {
	return verifier.ExpectSuccessfulRequest()
}