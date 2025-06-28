package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case generic/3.3/1: Sends a PRIORITY frame with priority 1.
// The client should accept PRIORITY frame with priority 1.
func RunTestGeneric3_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.3/1...")

	// Send PRIORITY frame with weight 1 (priority 1)
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, // Stream Dependency: 0 (no dependency)
		0x01,             // Weight: 1 (priority 1)
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with priority 1 - client should accept")
}

// Test Case generic/3.3/2: Sends a PRIORITY frame with priority 256.
// The client should accept PRIORITY frame with priority 256.
func RunTestGeneric3_3_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.3/2...")

	// Send PRIORITY frame with weight 255 (priority 256)
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, // Stream Dependency: 0 (no dependency)
		0xFF,             // Weight: 255 (priority 256)
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with priority 256 - client should accept")
}

// Test Case generic/3.3/3: Sends a PRIORITY frame with stream dependency.
// The client should accept PRIORITY frame with stream dependency.
func RunTestGeneric3_3_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.3/3...")

	// Send PRIORITY frame with stream dependency on stream 2
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x02, // Stream Dependency: 2
		0x10,             // Weight: 16
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame with dependency: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with stream dependency - client should accept")
}

// Test Case generic/3.3/4: Sends a PRIORITY frame with exclusive.
// The client should accept PRIORITY frame with exclusive flag.
func RunTestGeneric3_3_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.3/4...")

	// Send PRIORITY frame with exclusive dependency (E bit set)
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x80, 0x00, 0x00, 0x02, // Stream Dependency: 2 with exclusive bit (E=1)
		0x10,             // Weight: 16
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame with exclusive: %v", err)
		return
	}
	log.Println("Sent PRIORITY frame with exclusive dependency - client should accept")
}

// Test Case generic/3.3/5: Sends a PRIORITY frame for an idle stream, then send a HEADERS frame.
// The client should respond to HEADERS frame.
func RunTestGeneric3_3_5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/3.3/5...")

	// Send PRIORITY frame for idle stream 1
	priorityFrame := []byte{
		0x00, 0x00, 0x05, // Length: 5 bytes
		0x02,             // Type: PRIORITY
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (idle)
		0x00, 0x00, 0x00, 0x00, // Stream Dependency: 0
		0x10,             // Weight: 16
	}

	if _, err := conn.Write(priorityFrame); err != nil {
		log.Printf("Failed to write PRIORITY frame for idle stream: %v", err)
		return
	}

	// Now send HEADERS frame to open the stream
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent PRIORITY for idle stream then HEADERS - client should respond")
}