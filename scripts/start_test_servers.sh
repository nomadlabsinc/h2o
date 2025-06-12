#!/bin/bash
set -euo pipefail

# Start embedded test servers script

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

# Configuration
HTTP1_PORT=8080
HTTP2_PORT=8443
HTTP2_ONLY_PORT=8447
SSL_CERT_PATH="spec/support/test_servers/ssl/cert.pem"
SSL_KEY_PATH="spec/support/test_servers/ssl/key.pem"

# PID file directory
PID_DIR="tmp/test_servers"
mkdir -p "$PID_DIR"

# Function to start a server in background
start_server() {
    local server_name="$1"
    local server_binary="$2"
    local server_args="$3"
    local pid_file="$PID_DIR/${server_name}.pid"

    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log_warn "$server_name is already running (PID: $(cat "$pid_file"))"
        return
    fi

    log_info "Starting $server_name..."
    nohup "$server_binary" $server_args > "tmp/test_servers/${server_name}.log" 2>&1 &
    echo $! > "$pid_file"

    # Wait a moment and check if it started successfully
    sleep 1
    if kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log_info "✅ $server_name started successfully (PID: $(cat "$pid_file"))"
    else
        log_error "❌ Failed to start $server_name"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to stop all servers
stop_servers() {
    log_info "Stopping all test servers..."

    for pid_file in "$PID_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            server_name=$(basename "$pid_file" .pid)
            pid=$(cat "$pid_file")

            if kill -0 "$pid" 2>/dev/null; then
                log_info "Stopping $server_name (PID: $pid)"
                kill "$pid"

                # Wait for graceful shutdown
                for i in {1..10}; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        break
                    fi
                    sleep 0.5
                done

                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    log_warn "Force killing $server_name"
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi

            rm -f "$pid_file"
        fi
    done

    log_info "All test servers stopped"
}

# Function to check server health
check_health() {
    local url="$1"
    local name="$2"
    local max_attempts=30

    log_info "Checking health of $name at $url"

    for i in $(seq 1 $max_attempts); do
        if curl -f -s -m 5 "$url" >/dev/null 2>&1; then
            log_info "✅ $name is healthy"
            return 0
        fi

        if [ $i -eq $max_attempts ]; then
            log_error "❌ $name failed health check after $max_attempts attempts"
            return 1
        fi

        echo -n "."
        sleep 1
    done
}

# Main script logic
case "${1:-start}" in
    build)
        log_info "Building test servers..."
        ./scripts/build_test_servers.sh
        ;;

    start)
        # Build Crystal HTTP/1.1 server if it doesn't exist
        if [ ! -f "bin/test_servers/http1_server" ]; then
            log_info "HTTP/1.1 server binary not found, building..."
            ./scripts/build_test_servers.sh
        fi

        # Create tmp directory for logs
        mkdir -p tmp/test_servers

        log_info "Starting real HTTP/2 test servers..."

        # Start HTTP/1.1 server (Crystal)
        start_server "http1" "bin/test_servers/http1_server" "-p $HTTP1_PORT -h 0.0.0.0"

        # Start real HTTP/2 server using Nginx
        log_info "Starting nginx HTTP/2 server..."
        nohup nginx -c "$PWD/spec/support/test_servers/nginx_http2.conf" > "tmp/test_servers/nginx_http2.log" 2>&1 &
        echo $! > "$PID_DIR/nginx_http2.pid"

        # Wait a moment and check if nginx started successfully
        sleep 2
        if kill -0 "$(cat "$PID_DIR/nginx_http2.pid")" 2>/dev/null; then
            log_info "✅ Nginx HTTP/2 server started successfully (PID: $(cat "$PID_DIR/nginx_http2.pid"))"
        else
            log_error "❌ Failed to start Nginx HTTP/2 server"
            rm -f "$PID_DIR/nginx_http2.pid"
        fi

        # Start real HTTP/2-only server using Caddy
        log_info "Starting caddy HTTP/2-only server..."
        nohup caddy run --config "$PWD/spec/support/test_servers/Caddyfile" > "tmp/test_servers/caddy_http2.log" 2>&1 &
        echo $! > "$PID_DIR/caddy_http2.pid"

        # Wait a moment and check if caddy started successfully
        sleep 2
        if kill -0 "$(cat "$PID_DIR/caddy_http2.pid")" 2>/dev/null; then
            log_info "✅ Caddy HTTP/2-only server started successfully (PID: $(cat "$PID_DIR/caddy_http2.pid"))"
        else
            log_error "❌ Failed to start Caddy HTTP/2-only server"
            rm -f "$PID_DIR/caddy_http2.pid"
        fi

        # Wait for servers to fully initialize
        log_info "Waiting for servers to initialize..."
        sleep 3

        # Health checks with real HTTP/2
        log_info "Performing health checks..."
        check_health "http://localhost:$HTTP1_PORT/health" "HTTP/1.1 server"

        # Test real HTTP/2 connections
        log_info "Checking health of Nginx HTTP/2 server at https://localhost:$HTTP2_PORT/health"
        if curl -k --http2 -f -s -m 5 "https://localhost:$HTTP2_PORT/health" >/dev/null 2>&1; then
            log_info "✅ Nginx HTTP/2 server is healthy (real HTTP/2)"
        else
            log_error "❌ Nginx HTTP/2 server failed health check"
        fi

        log_info "Checking health of Caddy HTTP/2-only server at https://localhost:$HTTP2_ONLY_PORT/health"
        if curl -k --http2 -f -s -m 5 "https://localhost:$HTTP2_ONLY_PORT/health" >/dev/null 2>&1; then
            log_info "✅ Caddy HTTP/2-only server is healthy (real HTTP/2)"
        else
            log_error "❌ Caddy HTTP/2-only server failed health check"
        fi

        log_info "🎉 All test servers are running!"
        log_info "HTTP/1.1 server: http://localhost:$HTTP1_PORT"
        log_info "HTTP/2 server: https://localhost:$HTTP2_PORT"
        log_info "HTTP/2-only server: https://localhost:$HTTP2_ONLY_PORT"
        ;;

    stop)
        stop_servers
        ;;

    restart)
        stop_servers
        sleep 2
        "$0" start
        ;;

    status)
        log_info "Test server status:"
        for pid_file in "$PID_DIR"/*.pid; do
            if [ -f "$pid_file" ]; then
                server_name=$(basename "$pid_file" .pid)
                pid=$(cat "$pid_file")

                if kill -0 "$pid" 2>/dev/null; then
                    log_info "$server_name: running (PID: $pid)"
                else
                    log_warn "$server_name: not running (stale PID file)"
                    rm -f "$pid_file"
                fi
            fi
        done
        ;;

    logs)
        log_info "Test server logs:"
        for log_file in tmp/test_servers/*.log; do
            if [ -f "$log_file" ]; then
                server_name=$(basename "$log_file" .log)
                echo -e "${GREEN}=== $server_name ===${NC}"
                tail -20 "$log_file" || true
                echo
            fi
        done
        ;;

    *)
        echo "Usage: $0 {build|start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  build   - Build test server binaries"
        echo "  start   - Start all test servers (builds if needed)"
        echo "  stop    - Stop all test servers"
        echo "  restart - Restart all test servers"
        echo "  status  - Show test server status"
        echo "  logs    - Show test server logs"
        exit 1
        ;;
esac
