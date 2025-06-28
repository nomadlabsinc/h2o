package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 4.2/1: Sends a DATA frame with 2^14 octets in length.
// The client should be capable of receiving and processing frames up to 2^14 octets.
func RunTest4_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.2/1...")

	// Create a DATA frame with maximum default frame size (16384 = 2^14 bytes)
	frameSize := 16384
	frame := make([]byte, 9+frameSize)
	
	// Frame header
	frame[0] = byte(frameSize >> 16)     // Length (high byte)
	frame[1] = byte(frameSize >> 8)      // Length (middle byte)
	frame[2] = byte(frameSize)           // Length (low byte)
	frame[3] = 0x00                      // Type: DATA
	frame[4] = 0x01                      // Flags: END_STREAM
	frame[5] = 0x00                      // Stream ID (4 bytes)
	frame[6] = 0x00
	frame[7] = 0x00
	frame[8] = 0x01

	// Fill payload with data
	for i := 9; i < len(frame); i++ {
		frame[i] = byte(i % 256)
	}

	if _, err := conn.Write(frame); err != nil {
		log.Printf("Failed to write maximum size DATA frame: %v", err)
		return
	}
	log.Println("Sent DATA frame with 2^14 octets - client should process successfully")
}

// Test Case 4.2/2: Sends a large size DATA frame that exceeds the SETTINGS_MAX_FRAME_SIZE.
// The client should detect a FRAME_SIZE_ERROR.
func RunTest4_2_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.2/2...")

	// Send a DATA frame larger than default max frame size (16384 bytes)
	frameSize := 16385 // One byte over the limit
	frame := make([]byte, 9+frameSize)
	
	// Frame header
	frame[0] = byte(frameSize >> 16)     // Length (high byte)
	frame[1] = byte(frameSize >> 8)      // Length (middle byte)
	frame[2] = byte(frameSize)           // Length (low byte)
	frame[3] = 0x00                      // Type: DATA
	frame[4] = 0x01                      // Flags: END_STREAM
	frame[5] = 0x00                      // Stream ID (4 bytes)
	frame[6] = 0x00
	frame[7] = 0x00
	frame[8] = 0x01

	// Fill payload with data
	for i := 9; i < len(frame); i++ {
		frame[i] = byte(i % 256)
	}

	if _, err := conn.Write(frame); err != nil {
		log.Printf("Failed to write oversized DATA frame: %v", err)
		return
	}
	log.Println("Sent oversized DATA frame - client should detect FRAME_SIZE_ERROR")
}

// Test Case 4.2/3: Sends a large size HEADERS frame that exceeds the SETTINGS_MAX_FRAME_SIZE.
// The client should detect a FRAME_SIZE_ERROR.
func RunTest4_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 4.2/3...")

	// Send a HEADERS frame larger than default max frame size (16384 bytes)
	frameSize := 16385 // One byte over the limit
	frame := make([]byte, 9+frameSize)
	
	// Frame header
	frame[0] = byte(frameSize >> 16)     // Length (high byte)
	frame[1] = byte(frameSize >> 8)      // Length (middle byte)
	frame[2] = byte(frameSize)           // Length (low byte)
	frame[3] = 0x01                      // Type: HEADERS
	frame[4] = 0x05                      // Flags: END_STREAM | END_HEADERS
	frame[5] = 0x00                      // Stream ID (4 bytes)
	frame[6] = 0x00
	frame[7] = 0x00
	frame[8] = 0x01

	// Fill payload with header data (starting with valid indexed header)
	frame[9] = 0x82 // :method: GET
	for i := 10; i < len(frame); i++ {
		frame[i] = byte(i % 256)
	}

	if _, err := conn.Write(frame); err != nil {
		log.Printf("Failed to write oversized HEADERS frame: %v", err)
		return
	}
	log.Println("Sent oversized HEADERS frame - client should detect FRAME_SIZE_ERROR")
}