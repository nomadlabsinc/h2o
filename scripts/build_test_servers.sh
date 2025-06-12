#!/bin/bash
set -euo pipefail

# Build embedded test servers script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create bin directory if it doesn't exist
mkdir -p bin/test_servers

log_info "Building test servers..."

# Build HTTP/1.1 test server (Crystal)
log_info "Building HTTP/1.1 test server"
crystal build spec/support/test_servers/http1_server.cr -o bin/test_servers/http1_server --release --no-debug

# Check if SSL certificates exist, generate if needed
SSL_CERT_PATH="spec/support/test_servers/ssl/cert.pem"
SSL_KEY_PATH="spec/support/test_servers/ssl/key.pem"

if [ ! -f "$SSL_CERT_PATH" ] || [ ! -f "$SSL_KEY_PATH" ]; then
    log_info "SSL certificates not found, generating self-signed certificates..."
    mkdir -p spec/support/test_servers/ssl

    # Generate self-signed certificate for testing
    openssl req -x509 -newkey rsa:4096 -keyout "$SSL_KEY_PATH" -out "$SSL_CERT_PATH" \
        -days 365 -nodes -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null || {
        log_warn "OpenSSL not available, using existing certificates if any"
    }

    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        log_info "✅ SSL certificates generated successfully"
    fi
else
    log_info "✅ SSL certificates already exist"
fi

# Validate nginx and caddy configurations
log_info "Validating server configurations..."

# Test nginx config
if command -v nginx >/dev/null 2>&1; then
    if nginx -t -c "$PWD/spec/support/test_servers/nginx_http2.conf" >/dev/null 2>&1; then
        log_info "✅ Nginx HTTP/2 configuration is valid"
    else
        log_warn "⚠️  Nginx HTTP/2 configuration has issues, but continuing..."
    fi
else
    log_warn "⚠️  Nginx not found in PATH"
fi

# Test caddy config
if command -v caddy >/dev/null 2>&1; then
    if caddy validate --config "$PWD/spec/support/test_servers/Caddyfile" >/dev/null 2>&1; then
        log_info "✅ Caddy HTTP/2 configuration is valid"
    else
        log_warn "⚠️  Caddy HTTP/2 configuration has issues, but continuing..."
    fi
else
    log_warn "⚠️  Caddy not found in PATH"
fi

log_info "✅ Test server setup completed successfully"
log_info "Available servers:"
log_info "  - bin/test_servers/http1_server (Crystal HTTP/1.1 on port 8080)"
log_info "  - nginx HTTP/2 server (real HTTP/2 on port 8443)"
log_info "  - caddy HTTP/2-only server (real HTTP/2 on port 8447)"
