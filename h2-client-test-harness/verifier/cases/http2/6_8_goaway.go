package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.8/1", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
}
