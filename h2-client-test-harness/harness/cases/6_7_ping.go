package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.7/1: Sends a PING frame.
// The client is expected to respond with a PING frame with the ACK flag.
func RunTest6_7_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.7/1...")

	pingData := [8]byte{'h', '2', 's', 'p', 'e', 'c'}
	if err := framer.WritePing(false, pingData); err != nil {
		log.Printf("Failed to write PING frame: %v", err)
		return
	}
	log.Println("Sent PING frame, awaiting ACK.")

	for {
		frame, err := framer.ReadFrame()
		if err != nil {
			log.Printf("Failed to read frame while waiting for PING ACK: %v", err)
			return
		}

		switch f := frame.(type) {
		case *http2.PingFrame:
			if !f.IsAck() {
				log.Println("Received a PING frame, but it was not an ACK.")
				return
			}
			if string(f.Data[:]) != string(pingData[:]) {
				log.Printf("Received PING ACK, but data does not match. Got %v", f.Data)
				return
			}
			log.Println("Received PING ACK with correct data. Test complete.")
			return // Success
		default:
			log.Printf("Ignoring frame of type %T while waiting for PING ACK.", f)
		}
	}
}

// Test Case 6.7/2: Sends a PING frame with ACK flag.
// The client is expected to not respond to the PING ACK, but respond to a subsequent PING.
func RunTest6_7_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.7/2...")

	// Send a PING with ACK, which the client should ignore.
	if err := framer.WritePing(true, [8]byte{'i', 'g', 'n', 'o', 'r', 'e'}); err != nil {
		log.Printf("Failed to write PING ACK frame: %v", err)
		return
	}
	log.Println("Sent PING ACK, which should be ignored.")

	// Send a normal PING, which the client should respond to.
	pingData := [8]byte{'r', 'e', 's', 'p', 'o', 'n', 'd'}
	if err := framer.WritePing(false, pingData); err != nil {
		log.Printf("Failed to write subsequent PING frame: %v", err)
		return
	}
	log.Println("Sent second PING frame, awaiting ACK.")

	for {
		frame, err := framer.ReadFrame()
		if err != nil {
			log.Printf("Failed to read frame while waiting for PING ACK: %v", err)
			return
		}

		switch f := frame.(type) {
		case *http2.PingFrame:
			if !f.IsAck() {
				log.Println("Received a PING frame, but it was not an ACK.")
				return
			}
			if string(f.Data[:]) != string(pingData[:]) {
				log.Printf("Received PING ACK, but data does not match expected for the second PING. Got %v", f.Data)
				return
			}
			log.Println("Received PING ACK for the second PING. Test complete.")
			return // Success
		default:
			log.Printf("Ignoring frame of type %T while waiting for PING ACK.", f)
		}
	}
}

// Test Case 6.7/3: Sends a PING frame with a non-zero stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_7_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.7/3...")

	// Frame Header: Length (8), Type (PING), Flags (0), StreamID (1)
	malformedFrame := []byte{
		0x00, 0x00, 0x08, // Length: 8
		0x06,             // Type: PING (0x6)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x01, // Stream ID: 1
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Payload
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed PING frame: %v", err)
		return
	}

	log.Println("Sent malformed PING frame with non-zero stream ID. Test complete.")
}

// Test Case 6.7/4: Sends a PING frame with a length other than 8.
// The client is expected to detect a FRAME_SIZE_ERROR.
func RunTest6_7_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.7/4...")

	// Frame Header: Length (6), Type (PING), Flags (0), StreamID (0)
	malformedFrame := []byte{
		0x00, 0x00, 0x06, // Length: 6
		0x06,             // Type: PING (0x6)
		0x00,             // Flags: 0
		0x00, 0x00, 0x00, 0x00, // Stream ID: 0
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Payload
	}

	if _, err := conn.Write(malformedFrame); err != nil {
		log.Printf("Failed to write malformed PING frame: %v", err)
		return
	}

	log.Println("Sent malformed PING frame with invalid length. Test complete.")
}
