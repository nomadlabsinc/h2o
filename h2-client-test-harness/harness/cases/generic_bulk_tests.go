package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.4/1: Sends a RST_STREAM frame.
func RunTestGeneric3_4_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.4/1...")

	// First open a stream
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

	// Send RST_STREAM frame
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
	log.Println("Sent RST_STREAM frame - client should accept")
}

// Test Case generic/3.9/1: Sends a WINDOW_UPDATE frame.
func RunTestGeneric3_9_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.9/1...")

	// Send WINDOW_UPDATE frame on connection
	windowFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (connection)
		0x00, 0x00, 0x01, 0x00, // Window Size Increment: 256
	}

	if _, err := conn.Write(windowFrame); err != nil {
		log.Printf("Failed to write WINDOW_UPDATE frame: %v", err)
		return
	}
	log.Println("Sent WINDOW_UPDATE frame - client should accept")
}

// Test Case generic/3.10/1: Sends a CONTINUATION frame.
func RunTestGeneric3_10_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.10/1...")

	// Send HEADERS frame without END_HEADERS
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x00,             // Flags: none (no END_HEADERS)
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}

	// Send CONTINUATION frame
	contFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x09,             // Type: CONTINUATION
		0x05,             // Flags: END_HEADERS | END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x84,             // Header: :path: /
	}

	if _, err := conn.Write(contFrame); err != nil {
		log.Printf("Failed to write CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame - client should accept")
}

// Test Case generic/4/1: Sends a GET request.
func RunTestGeneric4_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/4/1...")

	// Send complete GET request
	headersFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
		0x84,             // Header: :path: /
		0x86,             // Header: :scheme: http
		0x87,             // Header: :authority: localhost
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write GET request: %v", err)
		return
	}
	log.Println("Sent GET request - client should accept")
}

// Test Case generic/4/2: Sends a POST request.
func RunTestGeneric4_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/4/2...")

	// Send POST request with headers
	headersFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83,             // Header: :method: POST
		0x84,             // Header: :path: /
		0x86,             // Header: :scheme: http
		0x87,             // Header: :authority: localhost
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write POST headers: %v", err)
		return
	}

	// Send DATA frame with body
	dataFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write POST data: %v", err)
		return
	}
	log.Println("Sent POST request - client should accept")
}