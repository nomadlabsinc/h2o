package main

import (
    "crypto/tls"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
    
    "golang.org/x/net/http2"
)

func main() {
    testID := os.Getenv("TEST_ID")
    if testID == "" {
        testID = "default"
    }
    
    // Create TLS config
    cert, err := tls.LoadX509KeyPair("cert.pem", "key.pem")
    if err != nil {
        log.Fatal(err)
    }
    
    tlsConfig := &tls.Config{
        Certificates: []tls.Certificate{cert},
        NextProtos:   []string{"h2"},
    }
    
    // Create HTTP/2 server
    mux := http.NewServeMux()
    
    // Basic test endpoints
    mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "text/plain")
        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, "Test ID: %s", testID)
    })
    
    mux.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        // Simulate different test scenarios based on testID
        switch testID {
        case "3.5/1", "3.5/2":
            // Connection preface tests
            time.Sleep(10 * time.Millisecond)
        case "4.1/1", "4.1/2", "4.1/3":
            // Frame format tests
            w.Header().Set("X-Test", "frame-format")
        case "5.1/1", "5.1/2", "5.1/3":
            // Stream state tests
            w.Header().Set("X-Stream", "test")
        default:
            // Default response
            w.Header().Set("X-Default", "true")
        }
        
        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, "OK")
    })
    
    server := &http.Server{
        Addr:      ":8080",
        Handler:   mux,
        TLSConfig: tlsConfig,
    }
    
    http2.ConfigureServer(server, &http2.Server{
        MaxConcurrentStreams: 100,
    })
    
    log.Printf("Starting test harness for test %s on :8080", testID)
    fmt.Println("listening") // Important: compliance tests look for this
    
    log.Fatal(server.ListenAndServeTLS("", ""))
}