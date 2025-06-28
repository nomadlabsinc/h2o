package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.2/1: Sends a PUSH_PROMISE frame.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.2/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":authority", Value: "example.com"})

	if err := framer.WritePushPromise(http2.PushPromiseParam{
		StreamID:      streamID,
		PromiseID:     3,
		BlockFragment: buf.Bytes(),
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write PUSH_PROMISE frame: %v", err)
		return
	}
	log.Println("Sent PUSH_PROMISE frame. Test complete.")
}
