package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("5.1/1", test5_1_1)
	verifier.Register("5.1/2", test5_1_2)
	verifier.Register("5.1/3", test5_1_3)
	verifier.Register("5.1/4", test5_1_4)
	verifier.Register("5.1/5", test5_1_5)
	verifier.Register("5.1/6", test5_1_6)
	verifier.Register("5.1/7", test5_1_7)
	verifier.Register("5.1/8", test5_1_8)
	verifier.Register("5.1/9", test5_1_9)
	verifier.Register("5.1/10", test5_1_10)
	verifier.Register("5.1/11", test5_1_11)
	verifier.Register("5.1/12", test5_1_12)
	verifier.Register("5.1/13", test5_1_13)
}

// Test Case 5.1/1: idle: Sends a DATA frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_1() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "idle", "stream")
}

// Test Case 5.1/2: idle: Sends a RST_STREAM frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_2() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "idle", "stream")
}

// Test Case 5.1/3: idle: Sends a WINDOW_UPDATE frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_3() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "idle", "stream")
}

// Test Case 5.1/4: idle: Sends a CONTINUATION frame.
// Expected: Client should detect PROTOCOL_ERROR and close connection.
func test5_1_4() error {
	return verifier.ExpectConnectionError("PROTOCOL_ERROR", "idle", "stream")
}

// Test Case 5.1/5: half closed (remote): Sends a DATA frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_5() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/6: half closed (remote): Sends a HEADERS frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_6() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/7: half closed (remote): Sends a CONTINUATION frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_7() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/8: closed: Sends a DATA frame after sending RST_STREAM frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_8() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/9: closed: Sends a HEADERS frame after sending RST_STREAM frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_9() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/10: closed: Sends a CONTINUATION frame after sending RST_STREAM frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_10() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/11: closed: Sends a DATA frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_11() error {
	return verifier.ExpectStreamError(http2.ErrCodeStreamClosed)
}

// Test Case 5.1/12: closed: Sends a HEADERS frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_12() error {
	return verifier.ExpectConnectionError("STREAM_CLOSED", "closed", "stream")
}

// Test Case 5.1/13: closed: Sends a CONTINUATION frame.
// Expected: Client should detect STREAM_CLOSED error.
func test5_1_13() error {
	return verifier.ExpectConnectionError("STREAM_CLOSED", "closed", "stream")
}