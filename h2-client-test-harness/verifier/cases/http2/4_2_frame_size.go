package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("4.2/1", test4_2_1)
	verifier.Register("4.2/2", test4_2_2)
	verifier.Register("4.2/3", test4_2_3)
}

// Test Case 4.2/1: Sends a DATA frame with 2^14 octets in length.
// Expected: Client should process the maximum size frame successfully.
func test4_2_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case 4.2/2: Sends a large size DATA frame that exceeds the SETTINGS_MAX_FRAME_SIZE.
// Expected: Client should detect FRAME_SIZE_ERROR on the stream.
func test4_2_2() error {
	return verifier.ExpectStreamError(http2.ErrCodeFrameSize)
}

// Test Case 4.2/3: Sends a large size HEADERS frame that exceeds the SETTINGS_MAX_FRAME_SIZE.
// Expected: Client should detect FRAME_SIZE_ERROR on the connection.
func test4_2_3() error {
	return verifier.ExpectConnectionError("FRAME_SIZE_ERROR", "frame", "size")
}