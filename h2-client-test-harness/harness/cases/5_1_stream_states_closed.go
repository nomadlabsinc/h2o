package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.1/9: closed: Sends a HEADERS frame after sending RST_STREAM frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_9(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/9...")

	// First open stream with HEADERS frame
	headersFrame1 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame1); err != nil {
		log.Printf("Failed to write initial HEADERS frame: %v", err)
		return
	}

	// Send RST_STREAM to close the stream
	rstFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x03,             // Type: RST_STREAM
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x08, // Error Code: CANCEL
	}

	if _, err := conn.Write(rstFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame: %v", err)
		return
	}

	// Now send HEADERS frame on closed stream
	headersFrame2 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(headersFrame2); err != nil {
		log.Printf("Failed to write HEADERS frame on closed stream: %v", err)
		return
	}
	log.Println("Sent HEADERS frame after RST_STREAM - client should detect STREAM_CLOSED")
}

// Test Case 5.1/10: closed: Sends a CONTINUATION frame after sending RST_STREAM frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_10(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/10...")

	// First open stream with HEADERS frame
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send RST_STREAM to close the stream
	rstFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x03,             // Type: RST_STREAM
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x08, // Error Code: CANCEL
	}

	if _, err := conn.Write(rstFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame: %v", err)
		return
	}

	// Send CONTINUATION frame on closed stream
	contFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x09,             // Type: CONTINUATION
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(contFrame); err != nil {
		log.Printf("Failed to write CONTINUATION frame on closed stream: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame after RST_STREAM - client should detect STREAM_CLOSED")
}

// Test Case 5.1/11: closed: Sends a DATA frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_11(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/11...")

	// First open stream and close it normally with END_STREAM
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Now send DATA frame on closed stream
	dataFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write DATA frame on closed stream: %v", err)
		return
	}
	log.Println("Sent DATA frame on closed stream - client should detect STREAM_CLOSED")
}

// Test Case 5.1/12: closed: Sends a HEADERS frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_12(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/12...")

	// First open stream and close it normally with END_STREAM
	headersFrame1 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame1); err != nil {
		log.Printf("Failed to write initial HEADERS frame: %v", err)
		return
	}

	// Now send HEADERS frame on closed stream
	headersFrame2 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(headersFrame2); err != nil {
		log.Printf("Failed to write HEADERS frame on closed stream: %v", err)
		return
	}
	log.Println("Sent HEADERS frame on closed stream - client should detect STREAM_CLOSED")
}

// Test Case 5.1/13: closed: Sends a CONTINUATION frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_13(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/13...")

	// First open stream and close it normally with END_STREAM
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send CONTINUATION frame on closed stream
	contFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x09,             // Type: CONTINUATION
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(contFrame); err != nil {
		log.Printf("Failed to write CONTINUATION frame on closed stream: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame on closed stream - client should detect STREAM_CLOSED")
}