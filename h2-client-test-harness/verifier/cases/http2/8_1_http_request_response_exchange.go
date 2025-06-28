package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
	"golang.org/x/net/http2"
)

func init() {
	verifier.Register("8.1/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.1/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.1/2", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.1/3", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.1/4", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.2/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.2/2", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/2", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/3", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/4", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/5", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/6", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.3/7", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.6/1", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
	verifier.Register("8.1.2.6/2", func() error {
		return verifier.ExpectStreamError(http2.ErrCodeProtocol)
	})
}
