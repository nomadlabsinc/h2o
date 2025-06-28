package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.8/1: Sends a GOAWAY frame.
// The client should accept GOAWAY frame.
func RunTestGeneric3_8_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.8/1...")

	// Send GOAWAY frame
	goawayFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x07,             // Type: GOAWAY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x00, 0x00, 0x00, // Last Stream ID: 0
		0x00, 0x00, 0x00, 0x00, // Error Code: NO_ERROR
	}

	if _, err := conn.Write(goawayFrame); err != nil {
		log.Printf("Failed to write GOAWAY frame: %v", err)
		return
	}
	log.Println("Sent GOAWAY frame - client should accept")
}