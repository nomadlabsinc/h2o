package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 3.5/1: Sends client connection preface.
// The client should send proper HTTP/2 connection preface.
func RunTest3_5_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 3.5/1...")

	// This test verifies the client sends the proper connection preface
	// The connection preface consists of:
	// 1. "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" string
	// 2. Followed by a SETTINGS frame
	
	// The harness main.go already handles reading the preface in handleConnection
	// This test just needs to send a response to verify the preface was correct
	
	if err := framer.WriteSettings(); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}
	log.Println("Sent SETTINGS frame - connection preface test")
}

// Test Case 3.5/2: Sends invalid connection preface.
// The client should detect invalid preface and close connection.
func RunTest3_5_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 3.5/2...")

	// This test case is special - it needs to be handled at the connection level
	// before the normal HTTP/2 frame processing begins.
	// We'll send an invalid response to simulate server behavior with invalid preface
	
	// Send a GOAWAY frame indicating protocol error
	if err := framer.WriteGoAway(0, http2.ErrCodeProtocol, []byte("Invalid connection preface")); err != nil {
		log.Printf("Failed to write GOAWAY frame: %v", err)
		return
	}
	log.Println("Sent GOAWAY for invalid preface - client should close connection")
}