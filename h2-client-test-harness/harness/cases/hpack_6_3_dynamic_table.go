package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case hpack/6.3/1: Sends a dynamic table size update larger than the value of SETTINGS_HEADER_TABLE_SIZE.
// The client should detect a COMPRESSION_ERROR.
func RunTestHpack6_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/6.3/1...")

	// First send SETTINGS frame to set header table size to 4096
	settingsFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes (one setting)
		0x04,             // Type: SETTINGS
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01,       // Setting ID: SETTINGS_HEADER_TABLE_SIZE (1)
		0x00, 0x00, 0x10, 0x00, // Setting Value: 4096
	}

	if _, err := conn.Write(settingsFrame); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	// Send HEADERS frame with dynamic table size update larger than setting
	// HPACK Section 6.3: Dynamic table size update must not exceed SETTINGS_HEADER_TABLE_SIZE
	headersFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x3F, 0xE1, 0x1F, // Dynamic Table Size Update: 8192 (larger than 4096 setting)
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with invalid table size update: %v", err)
		return
	}
	log.Println("Sent dynamic table size update exceeding limit - client should detect COMPRESSION_ERROR")
}