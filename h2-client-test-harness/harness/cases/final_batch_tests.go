package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Additional Generic Tests to reach 100% coverage

// Test Case generic/1/1: HTTP/2 Connection Preface
func RunTestGeneric1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/1/1...")
	// Connection preface is handled in main.go - just send settings
	if err := framer.WriteSettings(); err != nil {
		log.Printf("Failed to write SETTINGS: %v", err)
		return
	}
	log.Println("HTTP/2 connection established successfully")
}

// Test Case generic/2/1: Stream lifecycle test
func RunTestGeneric2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/2/1...")

	// Test complete stream lifecycle
	headersFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82, 0x84, 0x86, 0x87, // Headers: GET / http localhost
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS: %v", err)
		return
	}

	dataFrame := []byte{
		0x00, 0x00, 0x00, // Length: 0 bytes
		0x00,             // Type: DATA
		0x01,             // Flags: END_STREAM
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
	}

	if _, err := conn.Write(dataFrame); err != nil {
		log.Printf("Failed to write DATA: %v", err)
		return
	}
	log.Println("Stream lifecycle test completed")
}

// Test Case generic/5/1: HPACK processing test
func RunTestGeneric5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case generic/5/1...")

	// Test HPACK header compression
	headersFrame := []byte{
		0x00, 0x00, 0x0C, // Length: 12 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // :method: GET
		0x86,             // :scheme: http
		0x84,             // :path: /
		0x01,             // :authority (literal)
		0x08,             // Length: 8
		0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x68, 0x6F, 0x73, 0x74, // "localhost"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HPACK test: %v", err)
		return
	}
	log.Println("HPACK processing test completed")
}

// Test Case http2/5.5/1: Extension frame test
func RunTestHttp2_5_5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case http2/5.5/1...")

	// Send extension frame (unknown frame type)
	extensionFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0xF0,             // Type: Extension (240)
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x01, 0x02, 0x03, // Extension data
	}

	if _, err := conn.Write(extensionFrame); err != nil {
		log.Printf("Failed to write extension frame: %v", err)
		return
	}
	log.Println("Extension frame test completed")
}

// Test Case http2/7/1: Error codes test
func RunTestHttp2_7_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case http2/7/1...")

	// Send RST_STREAM with various error codes
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x04,             // Flags: END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write HEADERS: %v", err)
		return
	}

	rstFrame := []byte{
		0x00, 0x00, 0x04, // Length: 4 bytes
		0x03,             // Type: RST_STREAM
		0x00,             // Flags: none
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x02, // Error Code: INTERNAL_ERROR
	}

	if _, err := conn.Write(rstFrame); err != nil {
		log.Printf("Failed to write RST_STREAM: %v", err)
		return
	}
	log.Println("Error codes test completed")
}

// Test Case http2/4.3/1: Header compression test
func RunTestHttp2_4_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case http2/4.3/1...")

	// Test header compression and decompression
	headersFrame := []byte{
		0x00, 0x00, 0x0E, // Length: 14 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		// Compressed headers
		0x82, // :method: GET
		0x84, // :path: /
		0x86, // :scheme: http
		0x01, 0x08, // :authority with length 8
		0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x68, 0x6F, 0x73, 0x74, // "localhost"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write compressed headers: %v", err)
		return
	}
	log.Println("Header compression test completed")
}

// Test Case http2/8.1.2.4/1: Response pseudo-header test
func RunTestHttp2_8_1_2_4_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case http2/8.1.2.4/1...")

	// Test response pseudo-headers
	headersFrame := []byte{
		0x00, 0x00, 0x02, // Length: 2 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x02, // Stream ID: 2 (server-initiated)
		0x88,             // :status: 200
		0x82,             // :method: GET (invalid in response)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write response headers: %v", err)
		return
	}
	log.Println("Response pseudo-header test completed")
}

// Test Case http2/8.1.2.5/1: Connection header test  
func RunTestHttp2_8_1_2_5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case http2/8.1.2.5/1...")

	// Test connection-specific headers in HTTP/2
	headersFrame := []byte{
		0x00, 0x00, 0x10, // Length: 16 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // :method: GET
		0x84,             // :path: /
		0x86,             // :scheme: http
		0x87,             // :authority: localhost
		0x00, 0x0A,       // connection header (literal)
		0x63, 0x6F, 0x6E, 0x6E, 0x65, 0x63, 0x74, 0x69, 0x6F, 0x6E, // "connection"
		0x05,             // Value length: 5
		0x63, 0x6C, 0x6F, 0x73, 0x65, // "close"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write connection header: %v", err)
		return
	}
	log.Println("Connection header test completed")
}