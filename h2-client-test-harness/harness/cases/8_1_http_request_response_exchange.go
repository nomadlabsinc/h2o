package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.1/1: Sends a second HEADERS frame without the END_STREAM flag.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1/1...")

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
	log.Println("Sent HEADERS frame.")

	if err := framer.WriteData(streamID, false, []byte("test")); err != nil {
		log.Printf("Failed to write DATA frame: %v", err)
		return
	}
	log.Println("Sent DATA frame.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-test", Value: "ok"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write second HEADERS frame: %v", err)
		return
	}
	log.Println("Sent second HEADERS frame, which should trigger an error. Test complete.")
}
