package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case hpack/6.1/1: Sends a indexed header field representation with index 0.
// The client should detect a COMPRESSION_ERROR.
func RunTestHpack6_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/6.1/1...")

	// Send HEADERS frame with invalid indexed header field (index 0)
	// HPACK Section 6.1: Index 0 is not in the indexing tables
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x80, // Indexed Header Field with index 0 (invalid)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with invalid index: %v", err)
		return
	}
	log.Println("Sent indexed header field with index 0 - client should detect COMPRESSION_ERROR")
}