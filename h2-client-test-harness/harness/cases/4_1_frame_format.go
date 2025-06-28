package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 4.1/1: Sends a frame with unknown type.
// The client should ignore and discard frames with unknown types.
func RunTest4_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.1/1...")

	// Send a frame with unknown type (255)
	// RFC 7540 Section 4.1: Implementations MUST ignore and discard unknown frame types
	unknownFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0xFF,             // Type: Unknown (255)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 8 bytes of payload
	}

	if _, err := conn.Write(unknownFrame); err != nil {
		log.Printf("Failed to write unknown frame type: %v", err)
		return
	}

	// Send a PING frame to verify connection is still active
	pingFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x06,             // Type: PING (6)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // PING payload
	}

	if _, err := conn.Write(pingFrame); err != nil {
		log.Printf("Failed to write PING frame: %v", err)
		return
	}
	log.Println("Sent unknown frame type followed by PING - client should ignore unknown frame and respond to PING")
}

// Test Case 4.1/2: Sends a frame with undefined flag.
// The client should ignore undefined flags.
func RunTest4_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.1/2...")

	// Send PING frame with all flags set (including undefined ones)
	// RFC 7540 Section 4.1: Flags that have no defined semantics are ignored
	pingFrameWithFlags := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x06,             // Type: PING (6)
		0xFF,             // Flags: all flags set (255) - most are undefined for PING
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // PING payload
	}

	if _, err := conn.Write(pingFrameWithFlags); err != nil {
		log.Printf("Failed to write PING frame with undefined flags: %v", err)
		return
	}
	log.Println("Sent PING frame with undefined flags - client should ignore undefined flags and process frame")
}

// Test Case 4.1/3: Sends a frame with reserved field bit.
// The client should ignore the reserved field bit value.
func RunTest4_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.1/3...")

	// Send PING frame with reserved bit set in stream ID
	// RFC 7540 Section 4.1: Reserved bit MUST remain unset when sending and MUST be ignored when receiving
	pingFrameWithReserved := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x06,             // Type: PING (6)
		0x00,             // Flags: none
		0x80, 0x00, 0x00, 0x00, // Stream ID: 0 with reserved bit set (0x80000000)
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // PING payload
	}

	if _, err := conn.Write(pingFrameWithReserved); err != nil {
		log.Printf("Failed to write PING frame with reserved bit: %v", err)
		return
	}
	log.Println("Sent PING frame with reserved bit set - client should ignore reserved bit and process frame")
}