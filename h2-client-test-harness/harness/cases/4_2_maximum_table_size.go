package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case hpack/4.2/1: Sends a dynamic table size update at the end of header block.
// The client is expected to detect a COMPRESSION_ERROR.
func RunTestHpack4_2_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/4.2/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	// Dynamic table size update with value 1
	buf.Write([]byte{0x21})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with dynamic table size update at the end. Test complete.")
}
