package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.5.2/1: Sends SETTINGS_ENABLE_PUSH with a value other than 0 or 1.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_5_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.2/1...")

	if err := framer.WriteSettings(http2.Setting{ID: http2.SettingEnablePush, Val: 2}); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent SETTINGS_ENABLE_PUSH with invalid value. Test complete.")
}

// Test Case 6.5.2/2: Sends SETTINGS_INITIAL_WINDOW_SIZE with a value > 2^31-1.
// The client is expected to detect a FLOW_CONTROL_ERROR.
func RunTest6_5_2_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.2/2...")

	if err := framer.WriteSettings(http2.Setting{ID: http2.SettingInitialWindowSize, Val: 2147483648}); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent SETTINGS_INITIAL_WINDOW_SIZE with invalid value. Test complete.")
}

// Test Case 6.5.2/3: Sends SETTINGS_MAX_FRAME_SIZE with a value < 16384.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_5_2_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.2/3...")

	if err := framer.WriteSettings(http2.Setting{ID: http2.SettingMaxFrameSize, Val: 16383}); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent SETTINGS_MAX_FRAME_SIZE with invalid value. Test complete.")
}

// Test Case 6.5.2/4: Sends SETTINGS_MAX_FRAME_SIZE with a value > 16777215.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_5_2_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.2/4...")

	if err := framer.WriteSettings(http2.Setting{ID: http2.SettingMaxFrameSize, Val: 16777216}); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}

	log.Println("Sent SETTINGS_MAX_FRAME_SIZE with invalid value. Test complete.")
}

// Test Case 6.5.2/5: Sends a SETTINGS frame with an unknown identifier.
// The client is expected to ignore the setting and not terminate the connection.
func RunTest6_5_2_5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.2/5...")

	// Send a setting with an unknown ID. The client should ignore this.
	if err := framer.WriteSettings(http2.Setting{ID: 0xFF, Val: 1}); err != nil {
		log.Printf("Failed to write SETTINGS frame with unknown ID: %v", err)
		return
	}
	log.Println("Sent SETTINGS frame with unknown ID.")

	// To verify the connection is still alive, we send a PING...
	pingData := [8]byte{1, 2, 3, 4, 5, 6, 7, 8}
	if err := framer.WritePing(false, pingData); err != nil {
		log.Printf("Failed to write PING frame: %v", err)
		return
	}
	log.Println("Sent PING frame, awaiting ACK.")

	// ...and expect a PING ACK in response.
	// We will loop, ignoring other frames, until we get the PING ACK or an error.
	for {
		frame, err := framer.ReadFrame()
		if err != nil {
			log.Printf("Failed to read frame after PING: %v", err)
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
			// Ignore other frames like WINDOW_UPDATE, etc.
			log.Printf("Ignoring frame of type %T while waiting for PING ACK.", f)
		}
	}
}
