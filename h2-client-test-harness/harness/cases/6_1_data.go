package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.1/1: Sends a DATA frame with 0x0 stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.1/1...")

	// Send a DATA frame with stream ID 0 (invalid)
	// RFC 7540 Section 6.1: DATA frames MUST be associated with a stream
	malformedFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte payload
		0x00,             // Type: DATA (0x0)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (invalid)
		0x48, // Payload: single byte "H"
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write DATA frame with stream ID 0: %v", err)
		return
	}
	log.Println("Sent DATA frame with stream ID 0 - client should detect PROTOCOL_ERROR")
}

// Test Case 6.1/2: Sends a DATA frame on the stream that is not in "open" or "half-closed (local)" state.
// The client is expected to detect a STREAM_CLOSED error.
func RunTest6_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.1/2...")

	// Send a DATA frame on stream ID 1 without opening the stream first
	// This violates RFC 7540 Section 6.1 - DATA frames can only be sent on open streams
	malformedFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes payload
		0x00,             // Type: DATA (0x0)
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // Payload: "Hello"
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write DATA frame on closed stream: %v", err)
		return
	}
	log.Println("Sent DATA frame on closed stream - client should detect STREAM_CLOSED error")
}

// Test Case 6.1/3: Sends a DATA frame with invalid pad length.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.1/3...")

	// Send a DATA frame with PADDED flag but invalid padding
	// Padding length >= payload length is invalid per RFC 7540 Section 6.1
	malformedFrame := []byte{
		0x00, 0x00, 0x02, // Length: 2 bytes total
		0x00,             // Type: DATA (0x0)
		0x08,             // Flags: PADDED (0x8)
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x05, // Pad Length: 5 (invalid - longer than remaining payload)
		0x48, // Payload: single byte "H"
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write DATA frame with invalid padding: %v", err)
		return
	}
	log.Println("Sent DATA frame with invalid padding - client should detect PROTOCOL_ERROR")
}