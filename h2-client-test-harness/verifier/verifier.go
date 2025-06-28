package verifier

import (
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"

	"golang.org/x/net/http2"
)

type VerifierFunc func() error

var testRegistry = make(map[string]VerifierFunc)

func Register(id string, f VerifierFunc) {
	if _, ok := testRegistry[id]; ok {
		panic("test case already registered: " + id)
	}
	testRegistry[id] = f
}

func GetTest(id string) (VerifierFunc, bool) {
	test, ok := testRegistry[id]
	return test, ok
}

func PrintAllTests() {
	fmt.Println("Available test cases:")
	keys := make([]string, 0, len(testRegistry))
	for k := range testRegistry {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Printf("  - %s\n", k)
	}
}

// newClient creates a new HTTP/2 client with our self-signed certificate.
func newClient() *http.Client {
	return &http.Client{
		Transport: &http2.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true, // We expect a self-signed cert
			},
			AllowHTTP: true,
		},
	}
}

// ExpectConnectionError performs a GET request and checks if the resulting
// error contains one of the expected error substrings. This is used for
// tests that should cause a connection-level error.
func ExpectConnectionError(expectedErrors ...string) error {
	client := newClient()
	_, err := client.Get("https://127.0.0.1:8080")
	if err == nil {
		return fmt.Errorf("expected a connection error, but got none")
	}

	for _, expected := range expectedErrors {
		if strings.Contains(err.Error(), expected) {
			log.Printf("Got expected error: %v", err)
			return nil // Test passed
		}
	}

	return fmt.Errorf("got an unexpected error: %v, expected one of: %v", err, expectedErrors)
}

// ExpectStreamError performs a GET request and checks if the resulting
// error is a stream error of the expected type.
func ExpectStreamError(expectedCode http2.ErrCode) error {
	client := newClient()
	resp, err := client.Get("https://127.0.0.1:8080")
	if err == nil {
		// The stream might have been reset after the response headers were received.
		// In this case, reading the body will expose the error.
		_, err = io.ReadAll(resp.Body)
		if err == nil {
			return fmt.Errorf("expected a stream error, but got a successful response")
		}
	}

	if se, ok := err.(http2.StreamError); ok {
		if se.Code == expectedCode {
			log.Printf("Got expected stream error: %v", se)
			return nil // Test passed
		}
		return fmt.Errorf("got stream error with code %v, but expected %v", se.Code, expectedCode)
	}

	return fmt.Errorf("got an unexpected error type: %T, expected http2.StreamError", err)
}

// ExpectSuccessfulRequest performs a GET request and expects it to succeed.
// This is used for tests where the client should ignore the frame and keep
// the connection open.
func ExpectSuccessfulRequest() error {
	client := newClient()
	resp, err := client.Get("https://127.0.0.1:8080")
	if err != nil {
		return fmt.Errorf("expected a successful request, but got an error: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected status 200 OK, but got %s", resp.Status)
	}

	log.Println("Got successful response as expected.")
	return nil
}
