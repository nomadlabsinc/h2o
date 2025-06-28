package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("6.9.1/1", test6_9_1_1)
	verifier.Register("6.9.1/2", test6_9_1_2)
	verifier.Register("6.9.1/3", test6_9_1_3)
}

// Test Case 6.9.1/1: Sends SETTINGS frame to set the initial window size to 1 and sends HEADERS frame.
// Expected: Client should respect flow control window and send appropriately sized DATA.
func test6_9_1_1() error {
	return verifier.ExpectSuccessfulRequest()
}

// Test Case 6.9.1/2: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1.
// Expected: Client should detect FLOW_CONTROL_ERROR and close connection.
func test6_9_1_2() error {
	return verifier.ExpectConnectionError("FLOW_CONTROL_ERROR", "window", "overflow")
}

// Test Case 6.9.1/3: Sends multiple WINDOW_UPDATE frames increasing the flow control window to above 2^31-1 on a stream.
// Expected: Client should detect FLOW_CONTROL_ERROR on the stream.
func test6_9_1_3() error {
	return verifier.ExpectStreamError(http2.ErrCodeFlowControl)
}