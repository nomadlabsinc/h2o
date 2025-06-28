package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("6.10/2", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.10/3", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.10/4", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.10/5", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
	verifier.Register("6.10/6", func() error {
		return verifier.ExpectConnectionError("PROTOCOL_ERROR")
	})
}
