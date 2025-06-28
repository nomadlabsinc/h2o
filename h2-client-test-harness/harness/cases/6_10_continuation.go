package cases

import (
	"bytes"
	"log"
	"net"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/hpack"
)

// Test Case 6.10/2: Sends a CONTINUATION frame followed by any frame other than CONTINUATION.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_10_2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.10/2...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    false,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with END_HEADERS=false.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-foo", Value: "bar"})

	if err := framer.WriteContinuation(streamID, false, buf.Bytes()); err != nil {
		log.Printf("Failed to write CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame with END_HEADERS=false.")

	if err := framer.WriteData(streamID, true, []byte("test")); err != nil {
		log.Printf("Failed to write DATA frame: %v", err)
		return
	}
	log.Println("Sent DATA frame, which should trigger an error. Test complete.")
}

// Test Case 6.10/3: Sends a CONTINUATION frame with 0x0 stream identifier.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_10_3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.10/3...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    false,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with END_HEADERS=false.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-foo", Value: "bar"})

	if err := framer.WriteContinuation(0, true, buf.Bytes()); err != nil {
		log.Printf("Failed to write CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent CONTINUATION frame with stream ID 0. Test complete.")
}

// Test Case 6.10/4: Sends a CONTINUATION frame preceded by a HEADERS frame with END_HEADERS flag.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_10_4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.10/4...")

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
	log.Println("Sent HEADERS frame with END_HEADERS=true.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-foo", Value: "bar"})

	if err := framer.WriteContinuation(streamID, true, buf.Bytes()); err != nil {
		log.Printf("Failed to write CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent unexpected CONTINUATION frame. Test complete.")
}

// Test Case 6.10/5: Sends a CONTINUATION frame preceded by a CONTINUATION frame with END_HEADERS flag.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_10_5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.10/5...")

	var streamID uint32 = 1
	var buf bytes.Buffer
	hpackEncoder := hpack.NewEncoder(&buf)
	hpackEncoder.WriteField(hpack.HeaderField{Name: ":status", Value: "200"})

	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      streamID,
		BlockFragment: buf.Bytes(),
		EndStream:     false,
		EndHeaders:    false,
	}); err != nil {
		log.Printf("Failed to write HEADERS frame: %v", err)
		return
	}
	log.Println("Sent HEADERS frame with END_HEADERS=false.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-foo", Value: "bar"})

	if err := framer.WriteContinuation(streamID, true, buf.Bytes()); err != nil {
		log.Printf("Failed to write first CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent first CONTINUATION frame with END_HEADERS=true.")

	buf.Reset()
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-bar", Value: "baz"})

	if err := framer.WriteContinuation(streamID, true, buf.Bytes()); err != nil {
		log.Printf("Failed to write second CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent second, unexpected CONTINUATION frame. Test complete.")
}

// Test Case 6.10/6: Sends a CONTINUATION frame preceded by a DATA frame.
// The client is expected to detect a PROTOCOL_ERROR.
func RunTest6_10_6(conn net.Conn, framer *http2.Framer) {
	log.Println("Running test case 6.10/6...")

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
	hpackEncoder.WriteField(hpack.HeaderField{Name: "x-foo", Value: "bar"})

	if err := framer.WriteContinuation(streamID, true, buf.Bytes()); err != nil {
		log.Printf("Failed to write CONTINUATION frame: %v", err)
		return
	}
	log.Println("Sent unexpected CONTINUATION frame. Test complete.")
}
