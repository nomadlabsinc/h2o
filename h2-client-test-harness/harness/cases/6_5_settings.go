package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.5/1: Sends a SETTINGS frame with ACK flag and a non-empty payload.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5/1...")

	// The h2spec test sends a 1-byte payload with an ACK SETTINGS frame.
	// A valid ACK SETTINGS frame must have a zero-length payload.
	// We must write this as a raw frame, as the library prevents this.
	
	// Frame Header: Length (1), Type (SETTINGS), Flags (ACK), StreamID (0)
	// Payload: One arbitrary byte (e.g., 0xFF)
	malformedFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1
		0x04,             // Type: SETTINGS (0x4)
		0x01,             // Flags: ACK (0x1)
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0xFF, // The illegal payload byte
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed SETTINGS ACK frame: %v", err)
		return
	}

	log.Println("Sent malformed SETTINGS ACK frame. Test complete.")
}

// Test Case 6.5/2: Sends a SETTINGS frame with a stream identifier other than 0x0.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_5_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5/2...")

	// A valid SETTINGS frame MUST have a stream identifier of 0.
	// We will send an empty SETTINGS frame but set the stream ID to 1.
	
	// Frame Header: Length (0), Type (SETTINGS), Flags (0), StreamID (1)
	malformedFrame := []byte{
		0x00, 0x00, 0x00, // Length: 0
		0x04,             // Type: SETTINGS (0x4)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent malformed SETTINGS frame with non-zero stream ID. Test complete.")
}

// Test Case 6.5/3: Sends a SETTINGS frame with a length other than a multiple of 6 octets.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_5_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5/3...")

	// A valid SETTINGS frame's payload must be a multiple of 6 bytes long.
	// We will send a SETTINGS frame with a 5-byte payload.
	
	// Frame Header: Length (5), Type (SETTINGS), Flags (0), StreamID (0)
	malformedFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5
		0x04,             // Type: SETTINGS (0x4)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x01, 0x02, 0x03, 0x04, 0x05, // 5-byte payload
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent malformed SETTINGS frame with invalid length. Test complete.")
}
