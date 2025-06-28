package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.8/1: Sends a GOAWAY frame with a non-zero stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_8_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.8/1...")

	// Frame Header: Length (8), Type (GOAWAY), Flags (0), StreamID (1)
	malformedFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8
		0x07,             // Type: GOAWAY (0x7)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, // Last-Stream-ID
		0x00, 0x00, 0x00, 0x00, // Error Code
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed GOAWAY frame: %v", err)
		return
	}

	log.Println("Sent malformed GOAWAY frame with non-zero stream ID. Test complete.")
}
