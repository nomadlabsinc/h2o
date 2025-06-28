package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.1/1: Sends a DATA frame.
// The client should accept a single DATA frame.
func RunTestGeneric3_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.1/1...")

	// Send HEADERS frame first to open stream
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send DATA frame
	dataFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write DATA frame: %v", err)
		return
	}
	log.Println("Sent single DATA frame - client should accept")
}

// Test Case generic/3.1/2: Sends multiple DATA frames.
// The client should accept multiple DATA frames.
func RunTestGeneric3_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.1/2...")

	// Send HEADERS frame first to open stream
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send first DATA frame
	dataFrame1 := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame1); err != nil {
		log.Printf("Failed to write first DATA frame: %v", err)
		return
	}

	// Send second DATA frame
	dataFrame2 := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes
		0x00,             // Type: DATA
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, // " World"
	}

	if _, err := conn.Write(dataFrame2); err != nil {
		log.Printf("Failed to write second DATA frame: %v", err)
		return
	}
	log.Println("Sent multiple DATA frames - client should accept")
}

// Test Case generic/3.1/3: Sends a DATA frame with padding.
// The client should accept DATA frame with padding.
func RunTestGeneric3_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.1/3...")

	// Send HEADERS frame first to open stream
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send DATA frame with padding
	dataFrame := []byte{
		0x00, 0x00, 0x09, // Length: 9 bytes (1 pad length + 5 data + 3 padding)
		0x00,             // Type: DATA
		0x09,             // Flags: PADDED | END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x03,             // Pad Length: 3
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
		0x00, 0x00, 0x00, // Padding
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write padded DATA frame: %v", err)
		return
	}
	log.Println("Sent DATA frame with padding - client should accept")
}