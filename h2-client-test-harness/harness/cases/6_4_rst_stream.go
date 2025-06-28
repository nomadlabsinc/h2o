package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.4/1: Sends a RST_STREAM frame with 0x0 stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_4_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.4/1...")

	// Send RST_STREAM frame with stream ID 0 (invalid)
	// RFC 7540 Section 6.4: RST_STREAM frames MUST be associated with a stream
	malformedFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes (correct for RST_STREAM)
		0x03,             // Type: RST_STREAM (0x3)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (invalid)
		0x00, 0x00, 0x00, 0x08, // Error Code: CANCEL (8)
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame with stream ID 0: %v", err)
		return
	}
	log.Println("Sent RST_STREAM frame with stream ID 0 - client should detect PROTOCOL_ERROR")
}

// Test Case 6.4/2: Sends a RST_STREAM frame on a idle stream.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_4_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.4/2...")

	// Send RST_STREAM frame on an idle stream (stream that was never opened)
	// RFC 7540 Section 6.4: RST_STREAM frames MUST NOT be sent for idle streams
	malformedFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes (correct for RST_STREAM)
		0x03,             // Type: RST_STREAM (0x3)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle stream)
		0x00, 0x00, 0x00, 0x08, // Error Code: CANCEL (8)
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame on idle stream: %v", err)
		return
	}
	log.Println("Sent RST_STREAM frame on idle stream - client should detect PROTOCOL_ERROR")
}

// Test Case 6.4/3: Sends a RST_STREAM frame with a length other than 4 octets.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_4_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.4/3...")

	// Send RST_STREAM frame with incorrect length (3 bytes instead of 4)
	// RFC 7540 Section 6.4: RST_STREAM frames MUST be exactly 4 octets
	malformedFrame := []byte{
		0x00, 0x00, 0x03, // Length: 3 bytes (incorrect)
		0x03,             // Type: RST_STREAM (0x3)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, // Error Code: truncated (missing 1 byte)
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame with incorrect length: %v", err)
		return
	}
	log.Println("Sent RST_STREAM frame with incorrect length - client should detect FRAME_SIZE_ERROR")
}