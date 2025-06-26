#!/usr/bin/env bash

# H2O Docker Test Wrapper
#
# Simple wrapper script to run tests inside Docker containers with proper dependencies.
# Supports running all tests or specific test subgroups in isolated environments.

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DOCKER_IMAGE="h2o-test"

# Default values
SUITE="all"
VERBOSE=false
CLEANUP=true
BUILD_IMAGE=true

log() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

usage() {
    cat << EOF
H2O Docker Test Wrapper

USAGE:
    $0 [OPTIONS] [SUITE]

SUITES:
    all           Run all tests (default)
    unit          Run unit tests only
    integration   Run integration tests only
    performance   Run performance tests only
    lint          Run linting checks only
    simd          Run SIMD optimizer tests only
    quick         Run unit tests and lint (fast feedback)

OPTIONS:
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message
    --no-cleanup        Don't remove containers after tests
    --no-build          Skip Docker image build
    --build-only        Only build the Docker image

EXAMPLES:
    $0                  # Run all tests
    $0 unit             # Run unit tests only
    $0 quick            # Run unit tests and lint for quick feedback
    $0 -v integration   # Run integration tests with verbose output
    $0 --build-only     # Just build the Docker image

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --no-build)
                BUILD_IMAGE=false
                shift
                ;;
            --build-only)
                BUILD_IMAGE=true
                SUITE="build-only"
                shift
                ;;
            all|unit|integration|performance|lint|simd|quick)
                SUITE="$1"
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

build_docker_image() {
    if [[ "$BUILD_IMAGE" == "true" ]]; then
        log "Building Docker test image..."

        # Create a simple Dockerfile for testing if it doesn't exist
        if [[ ! -f "$PROJECT_ROOT/Dockerfile.test" ]]; then
            cat > "$PROJECT_ROOT/Dockerfile.test" << 'EOF'
FROM robnomad/crystal:dev-hoard

# Install additional dependencies for testing
RUN apk update && apk add --no-cache \
    bash \
    curl \
    git \
    nginx \
    ca-certificates \
    openssl

# Set up workspace
WORKDIR /workspace

# Copy project files
COPY . .

# Install Crystal dependencies
RUN shards install

# Default command
CMD ["crystal", "spec"]
EOF
        fi

        if ! docker build -f "$PROJECT_ROOT/Dockerfile.test" -t "$DOCKER_IMAGE" "$PROJECT_ROOT"; then
            error "Failed to build Docker image"
            exit 1
        fi

        success "Docker image built successfully"
    fi
}

run_docker_command() {
    local cmd="$1"
    local container_name="h2o-test-$$"

    local docker_args=(
        "run"
        "--rm"
        "--name" "$container_name"
        "-v" "$PROJECT_ROOT:/workspace"
        "-w" "/workspace"
        "--user" "root"
    )

    if [[ "$VERBOSE" == "true" ]]; then
        docker_args+=("-e" "VERBOSE=1")
    fi

    if [[ "$CLEANUP" == "false" ]]; then
        # Remove --rm flag for debugging
        docker_args=("${docker_args[@]/--rm}")
        warn "Container will not be automatically removed: $container_name"
    fi

    log "Running: $cmd"

    if docker "${docker_args[@]}" "$DOCKER_IMAGE" bash -c "$cmd"; then
        success "Command completed successfully"
        return 0
    else
        error "Command failed"
        return 1
    fi
}

run_unit_tests() {
    log "Running unit tests..."
    run_docker_command "crystal spec spec/h2o/ --verbose"
}

run_integration_tests() {
    log "Running integration tests..."

    # Check if docker compose is available
    if ! docker compose version &> /dev/null; then
        error "docker compose is required for integration tests"
        return 1
    fi

    # Start integration services
    log "Starting integration test services..."
    cd "$PROJECT_ROOT/spec/integration"

    if ! docker compose up -d; then
        error "Failed to start integration services"
        return 1
    fi

    # Show service status
    docker compose ps

    cd "$PROJECT_ROOT"

    # Run integration tests using docker-compose exec approach
    log "Running integration tests in existing test container..."

    # Use the existing h2o-test service from main docker-compose.yml if it exists,
    # otherwise run a temporary container connected to the integration network
    if docker compose -f docker-compose.yml ps h2o-test | grep -q "h2o-test"; then
        # Use existing service
        result=0
        if docker compose -f docker-compose.yml exec -T h2o-test crystal spec spec/integration/ --verbose; then
            success "Integration tests completed successfully"
        else
            error "Integration tests failed"
            result=1
        fi
    else
        # Create a temporary container connected to integration network
        local network_name="integration_default"

        # Check if integration network exists
        if ! docker network inspect "$network_name" >/dev/null 2>&1; then
            error "Integration network $network_name not found"
            cd "$PROJECT_ROOT/spec/integration"
            docker-compose down
            cd "$PROJECT_ROOT"
            return 1
        fi

        local container_name="h2o-integration-test-$$"

        local docker_args=(
            "run"
            "--rm"
            "--name" "$container_name"
            "-v" "$PROJECT_ROOT:/workspace"
            "-w" "/workspace"
            "--user" "root"
            "--network" "$network_name"
        )

        if [[ "$VERBOSE" == "true" ]]; then
            docker_args+=("-e" "VERBOSE=1")
        fi

        # Set environment variables for test hosts
        docker_args+=(
            "-e" "TEST_HTTP2_HOST=nginx-h2"
            "-e" "TEST_HTTP2_PORT=443"
            "-e" "TEST_HTTP1_HOST=httpbin-h2"
            "-e" "TEST_HTTP1_PORT=80"
            "-e" "TEST_H2_ONLY_HOST=h2-only-server"
            "-e" "TEST_H2_ONLY_PORT=8447"
            "-e" "TEST_CADDY_HOST=caddy-h2"
            "-e" "TEST_CADDY_PORT=8444"
            "-e" "CI=true"
        )

        log "Running integration tests..."

        result=0
        if docker "${docker_args[@]}" "$DOCKER_IMAGE" bash -c "crystal spec spec/integration/ --verbose"; then
            success "Integration tests completed successfully"
        else
            error "Integration tests failed"
            result=1
        fi
    fi

    # Clean up integration services
    log "Stopping integration test services..."
    cd "$PROJECT_ROOT/spec/integration"
    docker compose down
    cd "$PROJECT_ROOT"

    return $result
}

run_lint_tests() {
    log "Running lint checks..."
    run_docker_command "
        echo 'Checking Crystal formatting...' &&
        crystal tool format --check &&
        echo 'Running Ameba linting...' &&
        bin/ameba src spec --exclude lib
    "
}

run_simd_tests() {
    log "Running SIMD optimizer tests..."
    run_docker_command "crystal spec spec/h2o/simd_optimizer_spec.cr --verbose"
}

run_all_tests() {
    log "Running all test suites..."

    local failed=0

    if ! run_unit_tests; then
        ((failed++))
        error "Unit tests failed"
    fi

    if ! run_integration_tests; then
        ((failed++))
        error "Integration tests failed"
    fi

    if ! run_performance_tests; then
        ((failed++))
        error "Performance tests failed"
    fi

    if ! run_lint_tests; then
        ((failed++))
        error "Lint tests failed"
    fi

    if [[ $failed -eq 0 ]]; then
        success "All test suites passed!"
        return 0
    else
        error "$failed test suite(s) failed"
        return 1
    fi
}

run_quick_tests() {
    log "Running quick test suite (unit + lint)..."

    local failed=0

    if ! run_unit_tests; then
        ((failed++))
        error "Unit tests failed"
    fi

    if ! run_lint_tests; then
        ((failed++))
        error "Lint tests failed"
    fi

    if [[ $failed -eq 0 ]]; then
        success "Quick test suite passed!"
        return 0
    else
        error "$failed test(s) failed"
        return 1
    fi
}

main() {
    parse_args "$@"

    log "H2O Docker Test Runner"
    log "Suite: $SUITE, Verbose: $VERBOSE, Cleanup: $CLEANUP"

    if [[ "$SUITE" == "build-only" ]]; then
        build_docker_image
        exit 0
    fi

    build_docker_image

    case "$SUITE" in
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        performance)
            run_performance_tests
            ;;
        lint)
            run_lint_tests
            ;;
        simd)
            run_simd_tests
            ;;
        quick)
            run_quick_tests
            ;;
        all)
            run_all_tests
            ;;
        *)
            error "Unknown test suite: $SUITE"
            usage
            exit 1
            ;;
    esac
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

main "$@"
