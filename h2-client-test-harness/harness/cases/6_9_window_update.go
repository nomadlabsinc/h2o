package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 6.9/1: Sends a WINDOW_UPDATE frame with a flow-control window increment of 0.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_9_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9/1...")

	if err := framer.WriteWindowUpdate(0, 0); err != nil {
		log.Printf("Failed to write WINDOW_UPDATE frame: %v", err)
		return
	}

	log.Println("Sent WINDOW_UPDATE with 0 increment. Test complete.")
}

// Test Case 6.9/2: Sends a WINDOW_UPDATE frame with a flow-control window increment of 0 on a stream.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_9_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9/2...")

	// To test a stream-specific error, we first need to create a stream.
	// We can do this by sending a HEADERS frame.
	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	
	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame to create stream 1.")

	if err := framer.WriteWindowUpdate(streamID, 0); err != nil {
		log.Printf("Failed to write WINDOW_UPDATE frame: %v", err)
		return
	}

	log.Println("Sent WINDOW_UPDATE with 0 increment on stream 1. Test complete.")
}

// Test Case 6.9/3: Sends a WINDOW_UPDATE frame with a length other than 4 octets.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_9_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.9/3...")

	// Frame Header: Length (3), Type (WINDOW_UPDATE), Flags (0), StreamID (0)
	malformedFrame := []byte{
		0x00, 0x00, 0x03, // Length: 3
		0x08,             // Type: WINDOW_UPDATE (0x8)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x00, 0x01, // Payload
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed WINDOW_UPDATE frame: %v", err)
		return
	}

	log.Println("Sent malformed WINDOW_UPDATE frame with invalid length. Test complete.")
}
