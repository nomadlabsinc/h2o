package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/2.3.3/1", func() error {
		return verifier.ExpectConnectionError("COMPRESSION_ERROR")
	})
	verifier.Register("hpack/2.3.3/2", func() error {
		return verifier.ExpectConnectionError("COMPRESSION_ERROR")
	})
}
