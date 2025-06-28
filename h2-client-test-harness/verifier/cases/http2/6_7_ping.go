package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.7/1", func() error {
		return verifier.ExpectSuccessfulRequest()
	})
	verifier.Register("6.7/2", func() error {
		return verifier.ExpectSuccessfulRequest()
	})
	verifier.Register("6.7/3", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.7/4", func() error {
		return verifier.ExpectConnectionError("FRAME_SIZE_ERROR")
	})
}
