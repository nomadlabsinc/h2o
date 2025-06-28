package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 5.1/1: idle: Sends a DATA frame.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/1...")

	// Send DATA frame on idle stream (stream that was never opened)
	dataFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle)
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write DATA frame on idle stream: %v", err)
		return
	}
	log.Println("Sent DATA frame on idle stream - client should detect PROTOCOL_ERROR")
}

// Test Case 5.1/2: idle: Sends a RST_STREAM frame.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/2...")

	// Send RST_STREAM frame on idle stream
	rstFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x03,             // Type: RST_STREAM
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle)
		0x00, 0x00, 0x00, 0x08, // Error Code: CANCEL
	}

	if _, err := conn.Write(rstFrame); err != nil {
		log.Printf("Failed to write RST_STREAM frame on idle stream: %v", err)
		return
	}
	log.Println("Sent RST_STREAM frame on idle stream - client should detect PROTOCOL_ERROR")
}

// Test Case 5.1/3: idle: Sends a WINDOW_UPDATE frame.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/3...")

	// Send WINDOW_UPDATE frame on idle stream
	windowFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle)
		0x00, 0x00, 0x00, 0x01, // Window Size Increment: 1
	}

	if _, err := conn.Write(windowFrame); err != nil {
		log.Printf("Failed to write WINDOW_UPDATE frame on idle stream: %v", err)
		return
	}
	log.Println("Sent WINDOW_UPDATE frame on idle stream - client should detect PROTOCOL_ERROR")
}

// Test Case 5.1/4: idle: Sends a CONTINUATION frame.
// The client should detect a PROTOCOL_ERROR.
func RunTest5_1_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/4...")

	// Send CONTINUATION frame on idle stream
	contFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x09,             // Type: CONTINUATION
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle)
		0x82, // Header: :method: GET
	}

	if _, err := conn.Write(contFrame); err != nil {
		log.Printf("Failed to write CONTINUATION frame on idle stream: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame on idle stream - client should detect PROTOCOL_ERROR")
}

// Test Case 5.1/5: half closed (remote): Sends a DATA frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/5...")

	// First open stream with HEADERS frame with END_STREAM (making it half-closed remote)
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

	// Now send DATA frame on half-closed (remote) stream
	dataFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x00,             // Type: DATA
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x48, 0x65, 0x6c, 0x6c, 0x6f, // "Hello"
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write DATA frame on half-closed stream: %v", err)
		return
	}
	log.Println("Sent DATA frame on half-closed (remote) stream - client should detect STREAM_CLOSED")
}

// Test Case 5.1/6: half closed (remote): Sends a HEADERS frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_6(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/6...")

	// First open stream with HEADERS frame with END_STREAM (making it half-closed remote)
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

	// Now send another HEADERS frame on half-closed (remote) stream
	headersFrame2 := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(headersFrame2); err != nil {
		log.Printf("Failed to write HEADERS frame on half-closed stream: %v", err)
		return
	}
	log.Println("Sent HEADERS frame on half-closed (remote) stream - client should detect STREAM_CLOSED")
}

// Test Case 5.1/7: half closed (remote): Sends a CONTINUATION frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_7(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/7...")

	// First open stream with HEADERS frame with END_STREAM (making it half-closed remote)
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

	// Send CONTINUATION frame on half-closed (remote) stream
	contFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x09,             // Type: CONTINUATION
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x83, // Header: :method: POST
	}

	if _, err := conn.Write(contFrame); err != nil {
		log.Printf("Failed to write CONTINUATION frame on half-closed stream: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame on half-closed (remote) stream - client should detect STREAM_CLOSED")
}

// Test Case 5.1/8: closed: Sends a DATA frame after sending RST_STREAM frame.
// The client should detect a STREAM_CLOSED error.
func RunTest5_1_8(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 5.1/8...")

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
	log.Println("Sent DATA frame after RST_STREAM - client should detect STREAM_CLOSED")
}