package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.1.2/1: Sends HEADERS frames that causes their advertised concurrent stream limit to be exceeded.
// The client should detect a PROTOCOL_ERROR or REFUSED_STREAM.
func RunTest5_1_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1.2/1...")

	// First send SETTINGS frame to limit concurrent streams to 1
	settingsFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes (one setting)
		0x04,             // Type: SETTINGS
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x03,       // Setting ID: SETTINGS_MAX_CONCURRENT_STREAMS (3)
		0x00, 0x00, 0x00, 0x01, // Setting Value: 1
	}

	if _, err := conn.Write(settingsFrame); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	// Send first HEADERS frame (should be accepted)
	headersFrame1 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS (keep stream open)
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame1); err != nil {
		log.Printf("Failed to write first HEADERS frame: %v", err)
		return
	}

	// Send second HEADERS frame (should exceed limit)
	headersFrame2 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x03, // Stream ID: 3
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame2); err != nil {
		log.Printf("Failed to write second HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frames exceeding concurrent stream limit - client should detect PROTOCOL_ERROR or REFUSED_STREAM")
}