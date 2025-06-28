package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case hpack/5.2/1: Sends a Huffman-encoded string literal representation with padding longer than 7 bits.
// The client should detect a COMPRESSION_ERROR.
func RunTestHpack5_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/5.2/1...")

	// Send HEADERS frame with Huffman-encoded string with invalid padding
	// HPACK Section 5.2: Padding must be the most-significant bits of EOS (11111111)
	headersFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00,             // Literal Header Field with Incremental Indexing (New Name)
		0x85,             // Huffman Encoded String (H=1, Length=5)
		0xFF, 0xFF, 0xFF, 0xFF, 0x00, // Invalid padding (should be all 1s for EOS)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with invalid Huffman padding: %v", err)
		return
	}
	log.Println("Sent Huffman string with invalid padding - client should detect COMPRESSION_ERROR")
}

// Test Case hpack/5.2/2: Sends a Huffman-encoded string literal representation padded by zero.
// The client should detect a COMPRESSION_ERROR.
func RunTestHpack5_2_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/5.2/2...")

	// Send HEADERS frame with Huffman-encoded string padded with zeros (invalid)
	headersFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00,             // Literal Header Field with Incremental Indexing (New Name)
		0x85,             // Huffman Encoded String (H=1, Length=5)
		0xFF, 0xFF, 0xFF, 0xFF, 0x00, // Padded with zero (invalid)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with zero padding: %v", err)
		return
	}
	log.Println("Sent Huffman string with zero padding - client should detect COMPRESSION_ERROR")
}

// Test Case hpack/5.2/3: Sends a Huffman-encoded string literal representation containing the EOS symbol.
// The client should detect a COMPRESSION_ERROR.
func RunTestHpack5_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/5.2/3...")

	// Send HEADERS frame with Huffman-encoded string containing EOS symbol
	// HPACK Section 5.2: EOS symbol MUST NOT appear in the string
	headersFrame := []byte{
		0x00, 0x00, 0x09, // Length: 9 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00,             // Literal Header Field with Incremental Indexing (New Name)
		0x86,             // Huffman Encoded String (H=1, Length=6)
		0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // EOS symbol (all 1s - 30 bits minimum)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with EOS symbol: %v", err)
		return
	}
	log.Println("Sent Huffman string with EOS symbol - client should detect COMPRESSION_ERROR")
}