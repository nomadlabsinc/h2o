package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/5.2/1", testHpack5_2_1)
	verifier.Register("hpack/5.2/2", testHpack5_2_2)
	verifier.Register("hpack/5.2/3", testHpack5_2_3)
}

// Test Case hpack/5.2/1: Sends a Huffman-encoded string literal representation with padding longer than 7 bits.
// Expected: Client should detect COMPRESSION_ERROR and close connection.
func testHpack5_2_1() error {
	return verifier.ExpectConnectionError("COMPRESSION_ERROR", "huffman", "padding")
}

// Test Case hpack/5.2/2: Sends a Huffman-encoded string literal representation padded by zero.
// Expected: Client should detect COMPRESSION_ERROR and close connection.
func testHpack5_2_2() error {
	return verifier.ExpectConnectionError("COMPRESSION_ERROR", "huffman", "padding")
}

// Test Case hpack/5.2/3: Sends a Huffman-encoded string literal representation containing the EOS symbol.
// Expected: Client should detect COMPRESSION_ERROR and close connection.
func testHpack5_2_3() error {
	return verifier.ExpectConnectionError("COMPRESSION_ERROR", "huffman", "eos")
}