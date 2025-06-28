package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.4.1/1: Sends an invalid PING frame for connection close.
// The client should close the TCP connection.
func RunTest5_4_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.4.1/1...")

	// Send invalid PING frame (wrong length - 7 bytes instead of 8)
	// RFC 7540 Section 6.7: PING frames MUST contain exactly 8 octets
	invalidPingFrame := []byte{
		0x00, 0x00, 0x07, // Length: 7 bytes (invalid)
		0x06,             // Type: PING
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // 7 bytes payload (invalid)
	}

	if _, err := conn.Write(invalidPingFrame); err != nil {
		log.Printf("Failed to write invalid PING frame: %v", err)
		return
	}
	log.Println("Sent invalid PING frame - client should close connection")
}

// Test Case 5.4.1/2: Sends an invalid PING frame to receive GOAWAY frame.
// The client should send a GOAWAY frame.
func RunTest5_4_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.4.1/2...")

	// Send PING frame with non-zero stream ID (invalid)
	// RFC 7540 Section 6.7: PING frames MUST have stream identifier 0
	invalidPingFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x06,             // Type: PING
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (invalid for PING)
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // 8 bytes payload
	}

	if _, err := conn.Write(invalidPingFrame); err != nil {
		log.Printf("Failed to write PING frame with invalid stream ID: %v", err)
		return
	}
	log.Println("Sent PING frame with invalid stream ID - client should send GOAWAY")
}