package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.9.1/1: Sends SETTINGS frame to set the initial window size to 1 and sends HEADERS frame.
// The client should respect the flow control window size.
func RunTest6_9_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9.1/1...")

	// Send SETTINGS frame to set initial window size to 1
	settingsFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6 bytes (one setting)
		0x04,             // Type: SETTINGS
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x04,       // Setting ID: SETTINGS_INITIAL_WINDOW_SIZE (4)
		0x00, 0x00, 0x00, 0x01, // Setting Value: 1
	}

	if _, err := conn.Write(settingsFrame); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	// Send HEADERS frame to open a stream
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
	log.Println("Sent SETTINGS with window size 1 - client should respect flow control")
}

// Test Case 6.9.1/2: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1.
// The client should detect a FLOW_CONTROL_ERROR.
func RunTest6_9_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9.1/2...")

	// Send WINDOW_UPDATE frame that causes connection window to overflow (2^31-1 = 2147483647)
	// Default initial window is 65535, so we need to add more than 2147483647 - 65535
	windowFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (connection level)
		0x7F, 0xFF, 0xFF, 0xFF, // Window Size Increment: 2147483647 (max int32)
	}

	if _, err := conn.Write(windowFrame); err != nil {
		log.Printf("Failed to write first WINDOW_UPDATE frame: %v", err)
		return
	}

	// Send another WINDOW_UPDATE to cause overflow
	windowFrame2 := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (connection level)
		0x00, 0x00, 0x00, 0x01, // Window Size Increment: 1
	}

	if _, err := conn.Write(windowFrame2); err != nil {
		log.Printf("Failed to write second WINDOW_UPDATE frame: %v", err)
		return
	}
	log.Println("Sent WINDOW_UPDATE causing overflow - client should detect FLOW_CONTROL_ERROR")
}

// Test Case 6.9.1/3: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1 on a stream.
// The client should detect a FLOW_CONTROL_ERROR.
func RunTest6_9_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9.1/3...")

	// First open a stream
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

	// Send WINDOW_UPDATE frame that causes stream window to overflow
	windowFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x7F, 0xFF, 0xFF, 0xFF, // Window Size Increment: 2147483647 (max int32)
	}

	if _, err := conn.Write(windowFrame); err != nil {
		log.Printf("Failed to write first WINDOW_UPDATE frame: %v", err)
		return
	}

	// Send another WINDOW_UPDATE to cause overflow
	windowFrame2 := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x08,             // Type: WINDOW_UPDATE
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x01, // Window Size Increment: 1
	}

	if _, err := conn.Write(windowFrame2); err != nil {
		log.Printf("Failed to write second WINDOW_UPDATE frame: %v", err)
		return
	}
	log.Println("Sent WINDOW_UPDATE causing stream overflow - client should detect FLOW_CONTROL_ERROR")
}