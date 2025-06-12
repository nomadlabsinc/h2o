#!/bin/bash
# Start test servers for integration testing

set -e

echo "Starting test servers..."

# Copy SSL certificates if needed
if [ -d "/workspace/spec/integration/ssl" ]; then
    mkdir -p /etc/nginx/ssl
    cp /workspace/spec/integration/ssl/* /etc/nginx/ssl/
fi

# Start nginx with custom config if available
if [ -f "/workspace/spec/integration/nginx.conf" ]; then
    cp /workspace/spec/integration/nginx.conf /etc/nginx/nginx.conf
fi
nginx

# Start Caddy if Caddyfile exists
if [ -f "/workspace/spec/integration/Caddyfile" ]; then
    caddy start --config /workspace/spec/integration/Caddyfile
fi

# Start Node.js HTTP/2 server if exists
if [ -f "/workspace/spec/integration/h2-only-server.js" ]; then
    cd /workspace/spec/integration
    node h2-only-server.js &
fi

echo "Test servers started successfully"

# Keep the script running
tail -f /dev/null
