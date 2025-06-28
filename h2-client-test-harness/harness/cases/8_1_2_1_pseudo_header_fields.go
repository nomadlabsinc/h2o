package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.1.2.1/1: Sends a HEADERS frame that contains a unknown pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_1_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.1/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":test", Value: "ok"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with unknown pseudo-header field. Test complete.")
}

// Test Case 8.1.2.1/2: Sends a HEADERS frame that contains the pseudo-header field defined for response.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_1_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.1/2...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with response pseudo-header field. Test complete.")
}

// Test Case 8.1.2.1/3: Sends a HEADERS frame that contains a pseudo-header field as trailers.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_1_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.1/3...")

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
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "POST"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write trailers with pseudo-header field: %v", err)
		return
	}
	log.Println("Sent trailers with pseudo-header field. Test complete.")
}

// Test Case 8.1.2.1/4: Sends a HEADERS frame that contains a pseudo-header field that appears in a header block after a regular header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_1_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.1/4...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-test", Value: "ok"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with pseudo-header after regular header. Test complete.")
}
