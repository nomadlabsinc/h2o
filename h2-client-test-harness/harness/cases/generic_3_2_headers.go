package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.2/1: Sends a HEADERS frame.
// The client should accept HEADERS frame.
func RunTestGeneric3_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.2/1...")

	// Send HEADERS frame
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame - client should accept")
}

// Test Case generic/3.2/2: Sends a HEADERS frame with padding.
// The client should accept HEADERS frame with padding.
func RunTestGeneric3_2_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.2/2...")

	// Send HEADERS frame with padding
	headersFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes (1 pad length + 1 header + 3 padding)
		0x01,             // Type: HEADERS
		0x0D,             // Flags: PADDED | END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x03,             // Pad Length: 3
		0x82,             // Header: :method: GET
		0x00, 0x00, 0x00, // Padding
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write padded HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with padding - client should accept")
}

// Test Case generic/3.2/3: Sends a HEADERS frame with priority.
// The client should accept HEADERS frame with priority.
func RunTestGeneric3_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.2/3...")

	// Send HEADERS frame with priority
	headersFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes (5 priority + 1 header)
		0x01,             // Type: HEADERS
		0x25,             // Flags: PRIORITY | END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, // Stream Dependency: 0 (no dependency)
		0x10,             // Weight: 16
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with priority: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with priority - client should accept")
}