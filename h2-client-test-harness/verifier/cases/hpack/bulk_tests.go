package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/2.3/1", testHpack2_3_1)
	verifier.Register("hpack/6.2/1", testHpack6_2_1)
	verifier.Register("hpack/6.2.2/1", testHpack6_2_2_1)
	verifier.Register("hpack/6.2.3/1", testHpack6_2_3_1)
	verifier.Register("hpack/4.1/1", testHpack4_1_1)
}

// Test Case hpack/2.3/1: Sends a header with static table entry.
func testHpack2_3_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case hpack/6.2/1: Sends a literal header field with incremental indexing.
func testHpack6_2_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case hpack/6.2.2/1: Sends a literal header field without indexing.
func testHpack6_2_2_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case hpack/6.2.3/1: Sends a literal header field never indexed.
func testHpack6_2_3_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case hpack/4.1/1: Sends a dynamic table size update.
func testHpack4_1_1() error {
	return verifier.ExpectSuccessfulRequest()
}