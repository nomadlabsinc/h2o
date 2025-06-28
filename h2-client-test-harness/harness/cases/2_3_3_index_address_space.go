package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case hpack/2.3.3/1: Sends a indexed header field representation with invalid index.
// The client is expected to detect a COMPRESSION_ERROR.
func RunTestHpack2_3_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/2.3.3/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	// Indexed header field representation with index 70 (invalid)
	buf.Write([]byte{0xC6})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with invalid indexed header field. Test complete.")
}

// Test Case hpack/2.3.3/2: Sends a literal header field representation with invalid index.
// The client is expected to detect a COMPRESSION_ERROR.
func RunTestHpack2_3_3_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case hpack/2.3.3/2...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	// Literal Header Field with Incremental Indexing (index=70 & value=empty)
	buf.Write([]byte{0x7F, 0x07, 0x00})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with invalid literal header field. Test complete.")
}
