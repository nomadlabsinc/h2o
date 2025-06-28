package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/6.1/1", testHpack6_1_1)
}

// Test Case hpack/6.1/1: Sends a indexed header field representation with index 0.
// Expected: Client should detect COMPRESSION_ERROR and close connection.
func testHpack6_1_1() error {
	return verifier.ExpectConnectionError("COMPRESSION_ERROR", "index", "hpack")
}