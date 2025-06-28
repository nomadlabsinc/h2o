package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("6.9/1", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.9/2", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("6.9/3", func() error {
		return verifier.ExpectConnectionError("FRAME_SIZE_ERROR")
	})
	verifier.Register("6.9.2/3", func() error {
		return verifier.ExpectConnectionError("FLOW_CONTROL_ERROR")
	})
}
