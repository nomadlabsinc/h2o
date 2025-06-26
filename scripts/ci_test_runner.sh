#!/bin/bash
set -euo pipefail

# CI Test Runner Script
# Inspired by Go and Rust HTTP2 libraries testing patterns

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-2}
TEST_TIMEOUT=${TEST_TIMEOUT:-300}  # 5 minutes default

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to run tests with retries
run_with_retry() {
    local cmd="$1"
    local description="$2"
    local attempt=1

    log_info "Running: $description"

    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Attempt $attempt/$MAX_RETRIES"

        if timeout $TEST_TIMEOUT bash -c "$cmd"; then
            log_info "✅ $description succeeded"
            return 0
        else
            log_warn "Attempt $attempt failed for: $description"

            if [ $attempt -lt $MAX_RETRIES ]; then
                log_info "Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            fi
        fi

        attempt=$((attempt + 1))
    done

    log_error "❌ $description failed after $MAX_RETRIES attempts"
    return 1
}

# Function to check service health
check_service_health() {
    local service_url="$1"
    local service_name="$2"
    local max_wait=60
    local waited=0

    log_info "Checking health of $service_name at $service_url"

    while [ $waited -lt $max_wait ]; do
        if curl -fsS -m 5 "$service_url" > /dev/null 2>&1; then
            log_info "✅ $service_name is healthy"
            return 0
        fi

        sleep 1
        waited=$((waited + 1))
        echo -n "."
    done

    echo
    log_error "❌ $service_name failed to become healthy after ${max_wait}s"
    return 1
}

# Function to start embedded test servers
start_test_servers() {
    log_info "Starting embedded test servers..."
    ./scripts/start_test_servers.sh start

    # Give servers time to fully initialize
    sleep 2

    # Verify servers are running
    ./scripts/start_test_servers.sh status
}

# Function to stop embedded test servers
stop_test_servers() {
    log_info "Stopping embedded test servers..."
    ./scripts/start_test_servers.sh stop || true
}

# Main test execution
main() {
    log_info "Starting CI test runner"
    log_info "Environment: CRYSTAL_LOG_LEVEL=${CRYSTAL_LOG_LEVEL:-INFO}"
    log_info "Environment: CRYSTAL_LOG_SOURCES=${CRYSTAL_LOG_SOURCES:-h2o.*}"

    # Export debugging environment
    export CRYSTAL_LOG_LEVEL=${CRYSTAL_LOG_LEVEL:-DEBUG}
    export CRYSTAL_LOG_SOURCES=${CRYSTAL_LOG_SOURCES:-"h2o.*"}

    # Track overall success
    overall_success=true

    # Setup cleanup trap to stop servers on exit
    trap stop_test_servers EXIT

    # Run different test suites based on argument
    case "${1:-all}" in
        unit)
            log_info "Running unit tests with GNU parallel distribution"

            # Create list of unit test files for parallel execution (performance tests excluded)
            unit_tests=(
                "spec/h2o_spec.cr"
                "spec/h2o/circuit_breaker_spec.cr"
                "spec/h2o/connection_pooling_spec.cr"
                "spec/h2o/continuation_flood_protection_spec.cr"
                "spec/h2o/h1_client_spec.cr"
                "spec/h2o/hpack_security_spec.cr"
                "spec/h2o/io_optimization_spec.cr"
                "spec/h2o/response_type_spec.cr"
                "spec/h2o/ssl_verification_spec.cr"
                "spec/h2o/tls_spec.cr"
                "spec/h2o/frames/"
                "spec/h2o/hpack/"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute unit tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${unit_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${unit_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Unit test: $test" || overall_success=false
                done
            fi
            ;;

        integration)
            log_info "Running all integration tests with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # Create list of integration test files for parallel execution
            integration_tests=(
                "spec/integration/channel_fix_test_spec.cr"
                "spec/integration/circuit_breaker_integration_spec.cr"
                "spec/integration/comprehensive_http2_validation_spec.cr"
                "spec/integration/connection_pooling_integration_spec.cr"
                "spec/integration/fast_test_helpers_spec.cr"
                "spec/integration/focused_integration_spec.cr"
                "spec/integration/focused_parallel_spec.cr"
                "spec/integration/frame_processing_integration_spec.cr"
                "spec/integration/h1_client_integration_spec.cr"
                "spec/integration/h2_client_timeout_integration_spec.cr"
                "spec/integration/http1_fallback_spec.cr"
                "spec/integration/http11_local_server_spec.cr"
                "spec/integration/http2_frame_processing_spec.cr"
                "spec/integration/http2_integration_spec.cr"
                "spec/integration/http2_protocol_compliance_spec.cr"
                "spec/integration/improved_integration_spec.cr"
                "spec/integration/io_optimization_integration_spec.cr"
                "spec/integration/lazy_fiber_creation_spec.cr"
                "spec/integration/massively_parallel_spec.cr"
                "spec/integration/memory_management_integration_spec.cr"
                "spec/integration/minimal_integration_spec.cr"
                "spec/integration/real_https_integration_spec.cr"
                "spec/integration/regression_prevention_spec.cr"
                "spec/integration/ssl_verification_integration_spec.cr"
                "spec/integration/tls_integration_spec.cr"
                "spec/integration/tls_optimization_integration_spec.cr"
                "spec/integration/tls_socket_integration_spec.cr"
                "spec/integration/ultra_fast_integration_spec.cr"
                # New modular HTTP/2 tests for better parallelization
                "spec/integration/http2/basic_requests_spec.cr"
                "spec/integration/http2/content_types_spec.cr"
                "spec/integration/http2/status_codes_spec.cr"
                "spec/integration/http2/performance_spec.cr"
                "spec/integration/http2/error_handling_spec.cr"
                "spec/integration/http2/protocol_compliance_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group1)
            log_info "Running integration tests group 1 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # Fast integration tests (5-6 tests optimized for speed)
            integration_group1_tests=(
                "spec/integration/minimal_integration_spec.cr"
                "spec/integration/ultra_fast_integration_spec.cr"
                "spec/integration/fast_test_helpers_spec.cr"
                "spec/integration/focused_integration_spec.cr"
                "spec/integration/http2/basic_requests_spec.cr"
                "spec/integration/http2/status_codes_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 1 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group1_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group1_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group2)
            log_info "Running integration tests group 2 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # Medium-speed integration tests (5-6 tests)
            integration_group2_tests=(
                "spec/integration/channel_fix_test_spec.cr"
                "spec/integration/circuit_breaker_integration_spec.cr"
                "spec/integration/connection_pooling_integration_spec.cr"
                "spec/integration/http1_fallback_spec.cr"
                "spec/integration/http11_local_server_spec.cr"
                "spec/integration/http2/content_types_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 2 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group2_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group2_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group3)
            log_info "Running integration tests group 3 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # TLS and security focused tests (5-6 tests)
            integration_group3_tests=(
                "spec/integration/tls_integration_spec.cr"
                "spec/integration/tls_optimization_integration_spec.cr"
                "spec/integration/tls_socket_integration_spec.cr"
                "spec/integration/ssl_verification_integration_spec.cr"
                "spec/integration/h1_client_integration_spec.cr"
                "spec/integration/http2/error_handling_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 3 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group3_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group3_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group4)
            log_info "Running integration tests group 4 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # HTTP/2 protocol compliance tests (5 tests)
            integration_group4_tests=(
                "spec/integration/http2_integration_spec.cr"
                "spec/integration/http2_frame_processing_spec.cr"
                "spec/integration/http2_protocol_compliance_spec.cr"
                "spec/integration/frame_processing_integration_spec.cr"
                "spec/integration/http2/protocol_compliance_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 4 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group4_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group4_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group5)
            log_info "Running integration tests group 5 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # Performance and optimization tests (5 tests)
            integration_group5_tests=(
                "spec/integration/io_optimization_integration_spec.cr"
                "spec/integration/lazy_fiber_creation_spec.cr"
                "spec/integration/improved_integration_spec.cr"
                "spec/integration/h2_client_timeout_integration_spec.cr"
                "spec/integration/http2/performance_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 5 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group5_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group5_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        integration-group6)
            log_info "Running integration tests group 6 with GNU parallel distribution"

            # Start embedded test servers
            start_test_servers

            # Heavy/comprehensive tests (5 tests)
            integration_group6_tests=(
                "spec/integration/massively_parallel_spec.cr"
                "spec/integration/comprehensive_http2_validation_spec.cr"
                "spec/integration/memory_management_integration_spec.cr"
                "spec/integration/real_https_integration_spec.cr"
                "spec/integration/regression_prevention_spec.cr"
                "spec/integration/focused_parallel_spec.cr"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to distribute integration group 6 tests across 4 cores"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${integration_group6_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false
            else
                log_info "GNU parallel not available, running sequentially"
                for test in "${integration_group6_tests[@]}"; do
                    run_with_retry "crystal spec $test --verbose --error-trace" "Integration test: $test" || overall_success=false
                done
            fi
            ;;

        all)
            log_info "Running all test suites (excluding performance tests unless explicitly requested)"

            # Start embedded test servers for integration tests
            start_test_servers

            # Run all test suites using the optimized parallel approach
            log_info "Running unit tests"
            # Use unit test logic (performance tests already excluded)
            unit_tests=(
                "spec/h2o_spec.cr"
                "spec/h2o/circuit_breaker_spec.cr"
                "spec/h2o/connection_pooling_spec.cr"
                "spec/h2o/continuation_flood_protection_spec.cr"
                "spec/h2o/h1_client_spec.cr"
                "spec/h2o/hpack_security_spec.cr"
                "spec/h2o/io_optimization_spec.cr"
                "spec/h2o/response_type_spec.cr"
                "spec/h2o/ssl_verification_spec.cr"
                "spec/h2o/tls_spec.cr"
                "spec/h2o/frames/"
                "spec/h2o/hpack/"
            )

            if command -v parallel &> /dev/null; then
                log_info "Using GNU parallel to run all tests with maximum parallelization"
                # Create unique temp directories for each parallel job to avoid Crystal compilation conflicts
                printf '%s\n' "${unit_tests[@]}" | parallel -j4 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false

                # Run integration tests (note: these may need services running)
                integration_tests=($(find spec/integration -name "*.cr" | sort))
                printf '%s\n' "${integration_tests[@]}" | parallel -j2 --halt now,fail=1 \
                    'JOB_ID={#}; mkdir -p tmp/crystal_cache_$JOB_ID; CRYSTAL_CACHE_DIR=tmp/crystal_cache_$JOB_ID crystal spec {} --verbose --error-trace; rm -rf tmp/crystal_cache_$JOB_ID' || overall_success=false

            else
                # Fallback to sequential execution
                log_info "GNU parallel not available, running sequentially"
                run_with_retry "crystal spec spec/h2o_spec.cr spec/h2o/ --verbose --error-trace" "Unit tests" || overall_success=false
                run_with_retry "crystal spec spec/integration/ --verbose --error-trace" "Integration tests" || overall_success=false
            fi
            ;;

        *)
            log_error "Unknown test suite: $1"
            echo "Usage: $0 [unit|integration|integration-group1|integration-group2|integration-group3|integration-group4|integration-group5|integration-group6|performance|all]"
            exit 1
            ;;
    esac

    # Final report
    if [ "$overall_success" = true ]; then
        log_info "🎉 All tests passed!"
        exit 0
    else
        log_error "💥 Some tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"
