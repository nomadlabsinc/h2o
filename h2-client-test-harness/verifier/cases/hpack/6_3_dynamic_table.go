package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/6.3/1", testHpack6_3_1)
}

// Test Case hpack/6.3/1: Sends a dynamic table size update larger than the value of SETTINGS_HEADER_TABLE_SIZE.
// Expected: Client should detect COMPRESSION_ERROR and close connection.
func testHpack6_3_1() error {
	return verifier.ExpectConnectionError("COMPRESSION_ERROR", "table", "size")
}