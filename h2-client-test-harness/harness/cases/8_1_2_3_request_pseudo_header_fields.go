package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 8.1.2.3/1: Sends a HEADERS frame with empty ":path" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/1...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: ""})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with empty :path. Test complete.")
}

// Test Case 8.1.2.3/2: Sends a HEADERS frame that omits ":method" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/2...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame without :method. Test complete.")
}

// Test Case 8.1.2.3/3: Sends a HEADERS frame that omits ":scheme" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/3...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame without :scheme. Test complete.")
}

// Test Case 8.1.2.3/4: Sends a HEADERS frame that omits ":path" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/4...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame without :path. Test complete.")
}

// Test Case 8.1.2.3/5: Sends a HEADERS frame with duplicated ":method" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/5...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "POST"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with duplicated :method. Test complete.")
}

// Test Case 8.1.2.3/6: Sends a HEADERS frame with duplicated ":scheme" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_6(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/6...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with duplicated :scheme. Test complete.")
}

// Test Case 8.1.2.3/7: Sends a HEADERS frame with duplicated ":path" pseudo-header field.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest8_1_2_3_7(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 8.1.2.3/7...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":method", Value: "GET"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":scheme", Value: "https"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":path", Value: "/"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     true,
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with duplicated :path. Test complete.")
}
