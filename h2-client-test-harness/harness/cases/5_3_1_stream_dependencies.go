package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.3.1/1: Sends HEADERS frame that depends on itself.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_3_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.3.1/1...")

	// Send HEADERS frame with priority that depends on itself (stream 1 depends on stream 1)
	// RFC 7540 Section 5.3.1: A stream cannot depend on itself
	headersFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes (5 for priority + 1 for header)
		0x01,             // Type: HEADERS
		0x24,             // Flags: PRIORITY | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x01, // Stream Dependency: 1 (self-dependency - invalid)
		0x00,             // Weight: 0
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with self-dependency: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with self-dependency - client should detect PROTOCOL_ERROR")
}

// Test Case 5.3.1/2: Sends PRIORITY frame that depends on itself.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_3_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.3.1/2...")

	// First open a stream normally
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send PRIORITY frame that depends on itself
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x01, // Stream Dependency: 1 (self-dependency - invalid)
		0x00,             // Weight: 0
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame with self-dependency: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with self-dependency - client should detect PROTOCOL_ERROR")
}