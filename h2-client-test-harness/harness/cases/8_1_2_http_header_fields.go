package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.1.2/1: Sends a HEADERS frame that contains the header field name in uppercase letters.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: "X-TEST", Value: "ok"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with uppercase header field name. Test complete.")
}
