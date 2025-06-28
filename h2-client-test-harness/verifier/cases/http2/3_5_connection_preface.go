package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("3.5/1", test3_5_1)
	verifier.Register("3.5/2", test3_5_2)
}

// Test Case 3.5/1: Sends client connection preface.
// Expected: Client should establish connection successfully.
func test3_5_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case 3.5/2: Sends invalid connection preface.
// Expected: Client should detect protocol error and close connection.
func test3_5_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "preface", "connection")
}