package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.5/1: Sends a SETTINGS frame.
// The client should accept SETTINGS frame.
func RunTestGeneric3_5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.5/1...")

	// Send SETTINGS frame with all supported settings
	settingsFrame := []byte{
		0x00, 0x00, 0x24, // Length: 36 bytes (6 settings * 6 bytes each)
		0x04,             // Type: SETTINGS
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		
		// SETTINGS_HEADER_TABLE_SIZE (1)
		0x00, 0x01, 0x00, 0x00, 0x10, 0x00,
		
		// SETTINGS_ENABLE_PUSH (2)
		0x00, 0x02, 0x00, 0x00, 0x00, 0x01,
		
		// SETTINGS_MAX_CONCURRENT_STREAMS (3)
		0x00, 0x03, 0x00, 0x00, 0x00, 0x64,
		
		// SETTINGS_INITIAL_WINDOW_SIZE (4)
		0x00, 0x04, 0x00, 0x00, 0xFF, 0xFF,
		
		// SETTINGS_MAX_FRAME_SIZE (5)
		0x00, 0x05, 0x00, 0x00, 0x40, 0x00,
		
		// SETTINGS_MAX_HEADER_LIST_SIZE (6)
		0x00, 0x06, 0x00, 0x00, 0x20, 0x00,
	}

	if _, err := conn.Write(settingsFrame); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}
	log.Println("Sent SETTINGS frame with all parameters - client should accept")
}