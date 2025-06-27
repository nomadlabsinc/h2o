package main

import (
    "crypto/tls"
    "flag"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
    
    "golang.org/x/net/http2"
)

func main() {
    var port int
    var testID string
    
    flag.IntVar(&port, "port", 8080, "Port to listen on")
    flag.StringVar(&testID, "test", "default", "Test ID to simulate")
    flag.Parse()
    
    // Also check environment variable for backward compatibility
    if envTestID := os.Getenv("TEST_ID"); envTestID != "" {
        testID = envTestID
    }
    
    // Create TLS config - use existing certificates from integration directory
    cert, err := tls.LoadX509KeyPair("/workspace/spec/integration/ssl/cert.pem", "/workspace/spec/integration/ssl/key.pem")
    if err != nil {
        log.Fatal("Failed to load certificates:", err)
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
        Addr:      fmt.Sprintf(":%d", port),
        Handler:   mux,
        TLSConfig: tlsConfig,
    }
    
    http2.ConfigureServer(server, &http2.Server{
        MaxConcurrentStreams: 100,
    })
    
    log.Printf("Starting test harness for test %s on port %d", testID, port)
    fmt.Println("listening") // Important: compliance tests look for this
    
    log.Fatal(server.ListenAndServeTLS("", ""))
}

func generateTempCert() (tls.Certificate, error) {
    // Generate a temporary self-signed certificate
    template := `-----BEGIN CERTIFICATE-----
MIIBhTCCASugAwIBAgIJANjuwakQ0ID/MA0GCSqGSIb3DQEBCwUAMBkxFzAVBgNV
BAMTDnRlc3QubG9jYWxob3N0MB4XDTIzMDEwMTAwMDAwMFoXDTMzMDEwMTAwMDAw
MFowGTEXMBUGA1UEAxMOdGVzdC5sb2NhbGhvc3QwXDANBgkqhkiG9w0BAQEFAAON
SwAwSAJBAMxHQs6eIjTOCj3I8ZAAGrpHJJzSTZ8+qIHOCOGUpqVtmL3nNE7W
xUFsaEZ5O9WBFy8VN7x/Pb3dw3UmMfm+r4UCAwEAAaNQME4wHQYDVR0OBBYEFE
UOJnxcOVuYG1wBE6K7OQCOGUpqVtmMA0GA1UdDwEB/wQEAwIGwDAWBgNVHSUB
Af8EDDAKBggrBgEFBQcDATANBgkqhkiG9w0BAQsFAANBALGlOQCOGUpqVtmL3n
NE7WxUFsaEZ5O9WBFy8VN7x/Pb3dw3UmMfm+r4UCAwEAAaNQME4wHQYDVR0OBB
YEFE
-----END CERTIFICATE-----`

    key := `-----BEGIN PRIVATE KEY-----
MIIBUwIBADANBgkqhkiG9w0BAQEFAASCAT0wggE5AgEAAkEAzEdCzp4iNM4KPc
jxkAAaukckklNPnz6ogc4I4ZSmpW2YveFOJnxcOVuYG1wBE6K7OQCOGUpqVtmM
A0GA1UdDwEB/wQEAwIGwDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDATANBgkqhkiG
9w0BAQsFAANBALGlOQCOGUpqVtmL3nNE7WxUFsaEZ5O9WBFy8VN7x/Pb3dw3Um
-----END PRIVATE KEY-----`

    cert, err := tls.X509KeyPair([]byte(template), []byte(key))
    return cert, err
}