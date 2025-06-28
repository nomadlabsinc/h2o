package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.1.2.6/1: Sends a HEADERS frame with the "content-length" header field which does not equal the DATA frame payload length.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_6_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.6/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: "content-length", Value: "1"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with content-length: 1.")

	if err := framer.WriteData(streamID, true, []byte("test")); err != nil {
		log.Printf("Failed to write DATA frame: %v", err)
		return
	}
	log.Println("Sent DATA frame with actual length 4. Test complete.")
}

// Test Case 8.1.2.6/2: Sends a HEADERS frame with the "content-length" header field which does not equal the sum of the multiple DATA frames payload length.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_6_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.6/2...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: "content-length", Value: "1"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with content-length: 1.")

	if err := framer.WriteData(streamID, false, []byte("test")); err != nil {
		log.Printf("Failed to write first DATA frame: %v", err)
		return
	}
	log.Println("Sent first DATA frame.")

	if err := framer.WriteData(streamID, true, []byte("test")); err != nil {
		log.Printf("Failed to write second DATA frame: %v", err)
		return
	}
	log.Println("Sent second DATA frame. Test complete.")
}
