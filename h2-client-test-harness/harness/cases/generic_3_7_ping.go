package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.7/1: Sends a PING frame.
// The client should accept PING frame.
func RunTestGeneric3_7_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.7/1...")

	// Send PING frame
	pingFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x06,             // Type: PING
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // PING data
	}

	if _, err := conn.Write(pingFrame); err != nil {
		log.Printf("Failed to write PING frame: %v", err)
		return
	}
	log.Println("Sent PING frame - client should accept and respond")
}