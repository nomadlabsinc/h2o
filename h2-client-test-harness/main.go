package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"

	"github.com/nomadlabsinc/h2-client-test-harness/harness"
	"golang.org/x/net/http2"
)

func main() {
	testCaseID := flag.String("test", "", "The ID of the test case to run (e.g., '6.5/1')")
	flag.Parse()

	if *testCaseID == "" {
		fmt.Println("Usage: go run . --test=<test_case_id>")
		harness.PrintAllTests()
		os.Exit(1)
	}

	testFunc, ok := harness.GetTest(*testCaseID)
	if !ok {
		log.Fatalf("Test case '%s' not found.", *testCaseID)
	}

	if err := ensureCerts(); err != nil {
		log.Fatalf("Failed to create or find certificates: %v", err)
	}

	cert, err := tls.LoadX509KeyPair("cert.pem", "key.pem")
	if err != nil {
		log.Fatalf("Failed to load certificates: %v", err)
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		NextProtos:   []string{http2.NextProtoTLS},
	}

	listener, err := tls.Listen("tcp", "0.0.0.0:8080", tlsConfig)
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}
	defer listener.Close()

	log.Printf("Test harness server listening on %s for test case '%s'", listener.Addr().String(), *testCaseID)

	conn, err := listener.Accept()
	if err != nil {
		log.Fatalf("Failed to accept connection: %v", err)
	}
	
	handleConnection(conn, testFunc)
}

func handleConnection(conn net.Conn, testFunc harness.TestFunc) {
	defer conn.Close()
	log.Printf("Accepted connection from %s", conn.RemoteAddr())

	preface := make([]byte, len(http2.ClientPreface))
	if _, err := conn.Read(preface); err != nil {
		log.Printf("Failed to read client preface: %v", err)
		return
	}
	if string(preface) != http2.ClientPreface {
		log.Printf("Incorrect client preface received: %s", string(preface))
		return
	}
	log.Println("Client preface received.")

	framer := http2.NewFramer(conn, conn)
	frame, err := framer.ReadFrame()
	if err != nil {
		log.Printf("Failed to read client's initial SETTINGS frame: %v", err)
		return
	}
	if _, ok := frame.(*http2.SettingsFrame); !ok {
		log.Printf("Expected a SETTINGS frame from client, but got %T", frame)
		return
	}
	log.Println("Client's initial SETTINGS frame received.")

	if err := framer.WriteSettings(); err != nil {
		log.Printf("Failed to write initial server SETTINGS frame: %v", err)
		return
	}
	log.Println("Initial server SETTINGS frame sent.")

	testFunc(conn, framer)
}

func ensureCerts() error {
	if _, err := os.Stat("cert.pem"); os.IsNotExist(err) {
		log.Println("Certificate 'cert.pem' not found, generating new one...")
		cmd := exec.Command("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem", "-out", "cert.pem", "-days", "365", "-subj", "/CN=localhost")
		cmd.Dir = "."
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("failed to generate certificate: %s\n%s", err, string(out))
		}
		log.Println("Successfully generated cert.pem and key.pem.")
	}
	return nil
}
