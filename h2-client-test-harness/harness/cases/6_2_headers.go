package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.2/1: Sends a HEADERS frame without the END_HEADERS flag, and a PRIORITY frame.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.2/1...")

	// Send HEADERS frame without END_HEADERS flag
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte payload
		0x01,             // Type: HEADERS (0x1)
		0x04,             // Flags: END_STREAM (0x4) - missing END_HEADERS (0x4)
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Payload: indexed header field (":method: GET")
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write incomplete HEADERS frame: %v", err)
		return
	}

	// Follow with PRIORITY frame (not CONTINUATION) - this violates RFC 7540
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY (0x2)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, 0x00, // Priority data
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame: %v", err)
		return
	}
	log.Println("Sent incomplete HEADERS followed by PRIORITY - client should detect PROTOCOL_ERROR")
}

// Test Case 6.2/2: Sends a HEADERS frame to another stream while sending a HEADERS frame.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_2_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.2/2...")

	// Send HEADERS frame on stream 1 without END_HEADERS
	headersFrame1 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte payload
		0x01,             // Type: HEADERS (0x1)
		0x00,             // Flags: none (no END_HEADERS)
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Payload: indexed header field (":method: GET")
	}

	if _, err := conn.Write(headersFrame1); err != nil {
		log.Printf("Failed to write first HEADERS frame: %v", err)
		return
	}

	// Send HEADERS frame on stream 3 (different stream) - violates RFC 7540
	headersFrame3 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte payload  
		0x01,             // Type: HEADERS (0x1)
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x03, // Stream ID: 3
		0x82, // Payload: indexed header field (":method: GET")
	}

	if _, err := conn.Write(headersFrame3); err != nil {
		log.Printf("Failed to write second HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS on different streams simultaneously - client should detect PROTOCOL_ERROR")
}

// Test Case 6.2/3: Sends a HEADERS frame with 0x0 stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.2/3...")

	// Send HEADERS frame with stream ID 0 (invalid)
	malformedFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte payload
		0x01,             // Type: HEADERS (0x1)
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (invalid)
		0x82, // Payload: indexed header field (":method: GET")
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with stream ID 0: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with stream ID 0 - client should detect PROTOCOL_ERROR")
}

// Test Case 6.2/4: Sends a HEADERS frame with invalid pad length.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_2_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.2/4...")

	// Send HEADERS frame with PADDED flag but invalid padding
	malformedFrame := []byte{
		0x00, 0x00, 0x02, // Length: 2 bytes total
		0x01,             // Type: HEADERS (0x1)
		0x0D,             // Flags: PADDED | END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x05, // Pad Length: 5 (invalid - longer than remaining payload)
		0x82, // Payload: indexed header field (":method: GET")
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write HEADERS frame with invalid padding: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with invalid padding - client should detect PROTOCOL_ERROR")
}