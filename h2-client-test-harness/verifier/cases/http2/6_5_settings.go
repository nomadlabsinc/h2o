package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.5/1", func() error {
		return verifier.ExpectConnectionError("FRAME_SIZE_ERROR")
	})
	verifier.Register("6.5/2", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.5/3", func() error {
		return verifier.ExpectConnectionError("FRAME_SIZE_ERROR", "PROTOCOL_ERROR")
	})
	verifier.Register("6.5.2/1", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.5.2/2", func() error {
		return verifier.ExpectConnectionError("FLOW_CONTROL_ERROR")
	})
	verifier.Register("6.5.2/3", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.5.2/4", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.5.2/5", func() error {
		return verifier.ExpectSuccessfulRequest()
	})
	verifier.Register("6.5.3/2", func() error {
		return verifier.ExpectSuccessfulRequest()
	})
}
