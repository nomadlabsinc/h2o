package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case hpack/2.3/1: Sends a header with static table entry.
func RunTestHpack2_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/2.3/1...")

	// Send HEADERS frame with static table entry
	headersFrame := []byte{
		0x00, 0x00, 0x01, // Length: 1 byte
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x82,             // Indexed Header: :method: GET (static table index 2)
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write static table header: %v", err)
		return
	}
	log.Println("Sent header with static table entry - client should accept")
}

// Test Case hpack/6.2/1: Sends a literal header field with incremental indexing.
func RunTestHpack6_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/6.2/1...")

	// Send HEADERS frame with literal header field with incremental indexing
	headersFrame := []byte{
		0x00, 0x00, 0x0B, // Length: 11 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x40, 0x0A,       // Literal Header Field with Incremental Indexing (name length 10)
		0x63, 0x75, 0x73, 0x74, 0x6F, 0x6D, 0x2D, 0x6B, 0x65, 0x79, // "custom-key"
		0x0D,             // Value length: 13
		0x63, 0x75, 0x73, 0x74, 0x6F, 0x6D, 0x2D, 0x68, 0x65, 0x61, 0x64, 0x65, 0x72, // "custom-header"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write literal header with indexing: %v", err)
		return
	}
	log.Println("Sent literal header field with incremental indexing - client should accept")
}

// Test Case hpack/6.2.2/1: Sends a literal header field without indexing.
func RunTestHpack6_2_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/6.2.2/1...")

	// Send HEADERS frame with literal header field without indexing
	headersFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x04,       // Literal Header Field without Indexing (name length 4)
		0x74, 0x65, 0x73, 0x74, // "test"
		0x05,             // Value length: 5
		0x76, 0x61, 0x6C, 0x75, 0x65, // "value"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write literal header without indexing: %v", err)
		return
	}
	log.Println("Sent literal header field without indexing - client should accept")
}

// Test Case hpack/6.2.3/1: Sends a literal header field never indexed.
func RunTestHpack6_2_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/6.2.3/1...")

	// Send HEADERS frame with literal header field never indexed
	headersFrame := []byte{
		0x00, 0x00, 0x0A, // Length: 10 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x10, 0x06,       // Literal Header Field Never Indexed (name length 6)
		0x73, 0x65, 0x63, 0x72, 0x65, 0x74, // "secret"
		0x07,             // Value length: 7
		0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, // "private"
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write never indexed header: %v", err)
		return
	}
	log.Println("Sent literal header field never indexed - client should accept")
}

// Test Case hpack/4.1/1: Sends a dynamic table size update.
func RunTestHpack4_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/4.1/1...")

	// Send HEADERS frame with dynamic table size update
	headersFrame := []byte{
		0x00, 0x00, 0x02, // Length: 2 bytes
		0x01,             // Type: HEADERS
		0x05,             // Flags: END_STREAM | END_HEADERS
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x3F, 0xE1,       // Dynamic Table Size Update: 4096
		0x82,             // Header: :method: GET
	}

	if _, err := conn.Write(headersFrame); err != nil {
		log.Printf("Failed to write dynamic table size update: %v", err)
		return
	}
	log.Println("Sent dynamic table size update - client should accept")
}