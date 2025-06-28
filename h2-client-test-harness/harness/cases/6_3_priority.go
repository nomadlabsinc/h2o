package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.3/1: Sends a PRIORITY frame with 0x0 stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.3/1...")

	// Send PRIORITY frame with stream ID 0 (invalid)
	// RFC 7540 Section 6.3: PRIORITY frames MUST be associated with a stream
	malformedFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes (correct for PRIORITY)
		0x02,             // Type: PRIORITY (0x2)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (invalid)
		0x00, 0x00, 0x00, 0x01, // Stream Dependency: 1 (E=0)
		0x00, // Weight: 0
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame with stream ID 0: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with stream ID 0 - client should detect PROTOCOL_ERROR")
}

// Test Case 6.3/2: Sends a PRIORITY frame with a length other than 5 octets.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_3_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.3/2...")

	// Send PRIORITY frame with incorrect length (4 bytes instead of 5)
	// RFC 7540 Section 6.3: PRIORITY frames MUST be exactly 5 octets
	malformedFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes (incorrect)
		0x02,             // Type: PRIORITY (0x2)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x02, // Stream Dependency: 2 (E=0)
		// Missing weight byte - frame is truncated
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame with incorrect length: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with incorrect length - client should detect FRAME_SIZE_ERROR")
}