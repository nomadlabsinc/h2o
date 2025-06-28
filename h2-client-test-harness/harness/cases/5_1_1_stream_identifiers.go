package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.1.1/1: Sends even-numbered stream identifier.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1.1/1...")

	// Send HEADERS frame with even stream ID (invalid for client-initiated streams)
	// RFC 7540 Section 5.1.1: Client-initiated streams use odd stream identifiers
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x02, // Stream ID: 2 (even - invalid for client)
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with even stream ID: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with even stream ID - client should detect PROTOCOL_ERROR")
}

// Test Case 5.1.1/2: Sends stream identifier that is numerically smaller than previous.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1.1/2...")

	// First send HEADERS frame with stream ID 3
	headersFrame1 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x03, // Stream ID: 3
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame1); err != nil {
		log.Printf("Failed to write first HEADERS frame: %v", err)
		return
	}

	// Then send HEADERS frame with stream ID 1 (smaller than previous)
	// RFC 7540 Section 5.1.1: Stream identifiers must be monotonically increasing
	headersFrame2 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (smaller than previous 3)
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame2); err != nil {
		log.Printf("Failed to write second HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with decreasing stream ID - client should detect PROTOCOL_ERROR")
}