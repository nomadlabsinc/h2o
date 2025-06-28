package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.9.2/3: Sends a SETTINGS_INITIAL_WINDOW_SIZE settings with an exceeded maximum window size value.
// The client is expected to detect a FLOW_CONTROL_ERROR.
func RunTest6_9_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9.2/3...")

	// Frame Header: Length (6), Type (SETTINGS), Flags (0), StreamID (0)
	// Payload: SETTINGS_INITIAL_WINDOW_SIZE (0x4) with value 2147483648 (2^31)
	malformedFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6
		0x04,             // Type: SETTINGS (0x4)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x04,       // ID: SETTINGS_INITIAL_WINDOW_SIZE
		0x80, 0x00, 0x00, 0x00, // Value: 2147483648
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent malformed SETTINGS frame with invalid window size. Test complete.")
}
