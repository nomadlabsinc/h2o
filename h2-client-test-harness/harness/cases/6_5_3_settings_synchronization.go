package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Test Case 6.5.3/2: Sends a SETTINGS frame and expects an ACK.
// The client is expected to immediately send a SETTINGS frame with the ACK flag.
func RunTest6_5_3_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.5.3/2...")

	// Send a valid SETTINGS frame.
	if err := framer.WriteSettings(http2.Setting{ID: http2.SettingEnablePush, Val: 0}); err != nil {
		log.Printf("Failed to write SETTINGS frame: %v", err)
		return
	}
	log.Println("Sent SETTINGS frame, awaiting ACK.")

	// Expect a SETTINGS ACK in response.
	for {
		frame, err := framer.ReadFrame()
		if err != nil {
			log.Printf("Failed to read frame while waiting for SETTINGS ACK: %v", err)
			return
		}

		switch f := frame.(type) {
		case *http2.SettingsFrame:
			if !f.IsAck() {
				log.Println("Received a SETTINGS frame, but it was not an ACK.")
				return
			}
			log.Println("Received SETTINGS ACK. Test complete.")
			return // Success
		default:
			// Ignore other frames.
			log.Printf("Ignoring frame of type %T while waiting for SETTINGS ACK.", f)
		}
	}
}
