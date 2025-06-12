#!/bin/bash
set -euo pipefail

# Wait for Services Script
# Implements robust health checking patterns from Go/Rust HTTP2 libraries

# Configuration
MAX_WAIT=${MAX_WAIT:-120}  # Maximum wait time in seconds
CHECK_INTERVAL=${CHECK_INTERVAL:-2}  # Interval between checks

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Service definitions
declare -A SERVICES=(
    ["nginx-h2"]="https://127.0.0.1:8443/health"
    ["httpbin-h2"]="http://127.0.0.1:8080/health"
)

# Additional health endpoints to check
declare -A HEALTH_CHECKS=(
    ["nginx-h2-alt"]="https://127.0.0.1:8445/"
)

# Function to check a single service
check_service() {
    local name="$1"
    local url="$2"
    local protocol="${url%%://*}"

    case "$protocol" in
        https)
            curl -fsS -k -m 5 "$url" > /dev/null 2>&1
            ;;
        http)
            curl -fsS -m 5 "$url" > /dev/null 2>&1
            ;;
        *)
            echo -e "${RED}Unknown protocol: $protocol${NC}"
            return 1
            ;;
    esac
}

# Function to wait for a service with exponential backoff
wait_for_service() {
    local name="$1"
    local url="$2"
    local waited=0
    local backoff=1

    echo -n "Waiting for $name at $url "

    while [ $waited -lt $MAX_WAIT ]; do
        if check_service "$name" "$url"; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi

        echo -n "."
        sleep $backoff
        waited=$((waited + backoff))

        # Exponential backoff with cap
        if [ $backoff -lt 8 ]; then
            backoff=$((backoff * 2))
        fi
    done

    echo -e " ${RED}✗${NC}"
    echo -e "${RED}Service $name failed to become ready after ${MAX_WAIT}s${NC}"
    return 1
}

# Function to perform HTTP/2 specific checks
check_http2_support() {
    local url="$1"
    local name="$2"

    echo -n "Checking HTTP/2 support for $name "

    # Use nghttp if available for better HTTP/2 validation
    if command -v nghttp &> /dev/null; then
        if nghttp -nv "$url" 2>&1 | grep -q "HTTP/2"; then
            echo -e "${GREEN}✓${NC}"
            return 0
        fi
    else
        # Fallback to curl with HTTP/2
        if curl -fsS -k --http2 -I "$url" 2>&1 | grep -q "HTTP/2"; then
            echo -e "${GREEN}✓${NC}"
            return 0
        fi
    fi

    echo -e "${YELLOW}⚠ (HTTP/2 not confirmed)${NC}"
    return 0  # Don't fail, just warn
}

# Main execution
main() {
    echo -e "${GREEN}Starting service health checks...${NC}"
    echo "Configuration: MAX_WAIT=${MAX_WAIT}s, CHECK_INTERVAL=${CHECK_INTERVAL}s"

    local all_healthy=true

    # Check main services
    for service in "${!SERVICES[@]}"; do
        if ! wait_for_service "$service" "${SERVICES[$service]}"; then
            all_healthy=false
        fi
    done

    # Check additional health endpoints
    for check in "${!HEALTH_CHECKS[@]}"; do
        if ! wait_for_service "$check" "${HEALTH_CHECKS[$check]}"; then
            echo -e "${YELLOW}Warning: Secondary check $check failed${NC}"
        fi
    done

    # Perform HTTP/2 specific checks for HTTPS services
    if [ "$all_healthy" = true ]; then
        echo -e "\n${GREEN}Performing HTTP/2 validation...${NC}"
        for service in "${!SERVICES[@]}"; do
            url="${SERVICES[$service]}"
            if [[ "$url" == https://* ]]; then
                check_http2_support "$url" "$service"
            fi
        done
    fi

    # Docker compose status if available
    if [ "$all_healthy" = true ] && command -v docker &> /dev/null; then
        echo -e "\n${GREEN}Docker service status:${NC}"
        docker compose ps || true
    fi

    if [ "$all_healthy" = true ]; then
        echo -e "\n${GREEN}✅ All services are healthy and ready!${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some services failed health checks${NC}"

        # Dump logs for debugging
        if command -v docker &> /dev/null; then
            echo -e "\n${YELLOW}Recent container logs:${NC}"
            docker compose logs --tail=50 || true
        fi

        exit 1
    fi
}

# Handle script arguments
case "${1:-check}" in
    check)
        main
        ;;
    wait)
        # Simple wait mode without health checks
        echo "Waiting ${MAX_WAIT}s for services to start..."
        sleep $MAX_WAIT
        ;;
    *)
        echo "Usage: $0 [check|wait]"
        exit 1
        ;;
esac
