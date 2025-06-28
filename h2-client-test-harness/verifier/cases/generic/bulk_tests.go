package generic

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("generic/3.4/1", testGeneric3_4_1)
	verifier.Register("generic/3.9/1", testGeneric3_9_1)
	verifier.Register("generic/3.10/1", testGeneric3_10_1)
	verifier.Register("generic/4/1", testGeneric4_1)
	verifier.Register("generic/4/2", testGeneric4_2)
}

// Test Case generic/3.4/1: Sends a RST_STREAM frame.
func testGeneric3_4_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.9/1: Sends a WINDOW_UPDATE frame.
func testGeneric3_9_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/3.10/1: Sends a CONTINUATION frame.
func testGeneric3_10_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/4/1: Sends a GET request.
func testGeneric4_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case generic/4/2: Sends a POST request.
func testGeneric4_2() error {
	return verifier.ExpectSuccessfulRequest()
}