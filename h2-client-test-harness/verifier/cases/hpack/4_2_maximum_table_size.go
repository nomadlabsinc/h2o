package hpack

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	verifier.Register("hpack/4.2/1", func() error {
		return verifier.ExpectConnectionError("COMPRESSION_ERROR")
	})
}