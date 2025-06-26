#!/usr/bin/env bash

# H2O Docker Test Runner
#
# This script runs all tests inside Docker containers using the robnomad/crystal:dev-hoard base image.
# It provides comprehensive test reporting and supports different test suites for development and CI.

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
readonly DOCKER_IMAGE="h2o-dev"
readonly LOG_DIR="${PROJECT_ROOT}/test-logs"

# Default values
SUITE=""
VERBOSE=false
CLEANUP=true
PARALLEL=false
COVERAGE=false
INTEGRATION=true
PERFORMANCE=false
LINT=true
FORMAT_CHECK=true
BUILD_CHECK=true
DOCS=false

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_START_TIME=""

usage() {
    cat << EOF
H2O Docker Test Runner

USAGE:
    $0 [OPTIONS] [SUITE]

SUITES:
    all         Run all test suites (default)
    unit        Run only unit tests (fast)
    integration Run only integration tests
    performance Run performance benchmarks
    lint        Run linting and formatting checks
    build       Run build and documentation checks

OPTIONS:
    -v, --verbose        Enable verbose output
    -p, --parallel       Run tests in parallel where possible
    -c, --coverage       Generate test coverage report
    --no-integration     Skip integration tests
    --no-lint           Skip linting checks
    --no-format         Skip format checking
    --no-build          Skip build checks
    --no-cleanup        Keep Docker containers after tests
    --performance       Include performance tests
    --docs              Build documentation
    -h, --help          Show this help message

EXAMPLES:
    $0                   # Run all tests
    $0 unit              # Run only unit tests
    $0 -v --parallel     # Run all tests with verbose output and parallelization
    $0 integration -c    # Run integration tests with coverage
    $0 lint              # Run only linting checks

ENVIRONMENT:
    H2O_TEST_TIMEOUT     Test timeout in seconds (default: 300)
    H2O_TEST_RETRIES     Number of retries for flaky tests (default: 2)
    DOCKER_BUILDKIT      Enable Docker BuildKit (default: 1)

EOF
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${CYAN}[INFO]${NC}  ${timestamp} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} $message" ;;
        "DEBUG") [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} ${timestamp} $message" ;;
    esac
}

run_command() {
    local description="$1"
    shift
    local cmd="$*"

    log "INFO" "Running: $description"
    log "DEBUG" "Command: $cmd"

    local start_time=$(date +%s)
    local exit_code=0

    if [[ "$VERBOSE" == "true" ]]; then
        eval "$cmd" || exit_code=$?
    else
        eval "$cmd" >/dev/null 2>&1 || exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS" "$description completed in ${duration}s"
        ((TESTS_PASSED++))
        return 0
    else
        log "ERROR" "$description failed in ${duration}s (exit code: $exit_code)"
        ((TESTS_FAILED++))
        return $exit_code
    fi
}

ensure_docker_image() {
    log "INFO" "Ensuring Docker image '$DOCKER_IMAGE' is available"

    if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        log "INFO" "Building Docker image '$DOCKER_IMAGE'"
        run_command "Build Docker image" \
            "cd '$PROJECT_ROOT' && docker build -f Dockerfile.dev -t '$DOCKER_IMAGE' ."
    else
        log "DEBUG" "Docker image '$DOCKER_IMAGE' already exists"
    fi
}

setup_test_environment() {
    log "INFO" "Setting up test environment"

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Set Docker BuildKit
    export DOCKER_BUILDKIT=1

    # Record start time
    TOTAL_START_TIME=$(date +%s)

    log "DEBUG" "Log directory: $LOG_DIR"
    log "DEBUG" "Project root: $PROJECT_ROOT"
}

docker_run() {
    local cmd="$1"
    local extra_args="${2:-}"

    # Base docker run command with common options
    local docker_cmd="docker run --rm \
        -v '$PROJECT_ROOT:/workspace' \
        -w /workspace \
        --user root \
        $extra_args \
        '$DOCKER_IMAGE' \
        bash -c '$cmd'"

    log "DEBUG" "Docker command: $docker_cmd"
    eval "$docker_cmd"
}

install_dependencies() {
    log "INFO" "Installing Crystal dependencies"
    run_command "Install shards" \
        "docker_run 'shards install'"
}

run_unit_tests() {
    log "INFO" "Running unit tests"

    local coverage_flag=""
    if [[ "$COVERAGE" == "true" ]]; then
        coverage_flag="--coverage"
    fi

    local unit_specs=(
        "spec/h2o_spec.cr"
        "spec/h2o/circuit_breaker_spec.cr"
        "spec/h2o/connection_pooling_spec.cr"
        "spec/h2o/continuation_flood_protection_spec.cr"
        "spec/h2o/frames/"
        "spec/h2o/h1_client_spec.cr"
        "spec/h2o/hpack/"
        "spec/h2o/hpack_security_spec.cr"
        "spec/h2o/io_optimization_spec.cr"
        "spec/h2o/response_type_spec.cr"
        "spec/h2o/tls_spec.cr"
        "spec/h2o/ssl_verification_spec.cr"
    )

    local specs_list=$(printf "%s " "${unit_specs[@]}")

    run_command "Unit tests" \
        "docker_run 'crystal spec $specs_list --verbose $coverage_flag'"
}

run_integration_tests() {
    log "INFO" "Running integration tests"

    # Start test servers first
    log "INFO" "Starting Docker test servers"
    run_command "Start test servers" \
        "cd '$PROJECT_ROOT/spec/integration' && docker compose up -d nginx-h2 httpbin-h2"

    # Wait for services to be ready
    log "INFO" "Waiting for test servers to be ready"
    sleep 2

    # Run integration tests with network access
    run_command "Integration tests" \
        "docker_run './scripts/ci_test_runner.sh integration' '--network host'"

    # Stop test servers
    if [[ "$CLEANUP" == "true" ]]; then
        log "INFO" "Stopping test servers"
        cd "$PROJECT_ROOT/spec/integration" && docker compose down >/dev/null 2>&1 || true
    fi
}

run_lint_checks() {
    log "INFO" "Running lint checks"

    if [[ "$FORMAT_CHECK" == "true" ]]; then
        run_command "Format check" \
            "docker_run 'crystal tool format --check'"
    fi

    run_command "Ameba linter" \
        "docker_run 'crystal run lib/ameba/bin/ameba.cr -- src/ spec/'"
}

run_build_checks() {
    log "INFO" "Running build checks"

    run_command "Release build" \
        "docker_run 'crystal build src/h2o.cr --release --no-debug'"

    if [[ "$DOCS" == "true" ]]; then
        run_command "Documentation build" \
            "docker_run 'crystal docs'"
    fi
}

run_parallel_tests() {
    log "INFO" "Running tests in parallel with enhanced concurrency"

    local pids=()

    # Start background jobs with more parallelization
    if [[ "$SUITE" == "all" || "$SUITE" == "unit" ]]; then
        run_unit_tests &
        pids+=($!)
    fi

    if [[ "$INTEGRATION" == "true" && ("$SUITE" == "all" || "$SUITE" == "integration") ]]; then
        run_integration_tests &
        pids+=($!)
    fi

    if [[ "$PERFORMANCE" == "true" && ("$SUITE" == "all" || "$SUITE" == "performance") ]]; then
        run_performance_tests &
        pids+=($!)
    fi

    if [[ "$LINT" == "true" && ("$SUITE" == "all" || "$SUITE" == "lint") ]]; then
        run_lint_checks &
        pids+=($!)
    fi

    if [[ "$BUILD_CHECK" == "true" && ("$SUITE" == "all" || "$SUITE" == "build") ]]; then
        run_build_checks &
        pids+=($!)
    fi

    # Wait for all background jobs
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done

    return $failed
}

generate_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - TOTAL_START_TIME))
    local total_tests=$((TESTS_PASSED + TESTS_FAILED))

    echo
    echo "======================================"
    echo "         TEST RESULTS SUMMARY"
    echo "======================================"
    echo "Total tests run: $total_tests"
    echo "Tests passed:    $TESTS_PASSED"
    echo "Tests failed:    $TESTS_FAILED"
    echo "Success rate:    $(( total_tests > 0 ? (TESTS_PASSED * 100) / total_tests : 0 ))%"
    echo "Total duration:  ${total_duration}s"
    echo "======================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Some tests failed. Check the output above for details.${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed successfully!${NC}"
        return 0
    fi
}

cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        log "INFO" "Cleaning up test environment"

        # Stop any running test servers
        cd "$PROJECT_ROOT/spec/integration" && docker compose down >/dev/null 2>&1 || true

        # Remove any temporary files
        rm -f "$PROJECT_ROOT"/*.log >/dev/null 2>&1 || true
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -c|--coverage)
                COVERAGE=true
                shift
                ;;
            --no-integration)
                INTEGRATION=false
                shift
                ;;
            --no-lint)
                LINT=false
                shift
                ;;
            --no-format)
                FORMAT_CHECK=false
                shift
                ;;
            --no-build)
                BUILD_CHECK=false
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --performance)
                PERFORMANCE=true
                shift
                ;;
            --docs)
                DOCS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            all|unit|integration|performance|lint|build)
                SUITE="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Default suite
    if [[ -z "$SUITE" ]]; then
        SUITE="all"
    fi

    # Set up trap for cleanup
    trap cleanup EXIT

    log "INFO" "Starting H2O test runner"
    log "INFO" "Suite: $SUITE, Verbose: $VERBOSE, Parallel: $PARALLEL, Coverage: $COVERAGE"

    # Setup
    setup_test_environment
    ensure_docker_image
    install_dependencies

    # Run tests based on suite and options
    case "$SUITE" in
        "all")
            if [[ "$PARALLEL" == "true" ]]; then
                run_parallel_tests
            else
                run_unit_tests
                [[ "$INTEGRATION" == "true" ]] && run_integration_tests
                [[ "$PERFORMANCE" == "true" ]] && run_performance_tests
                [[ "$LINT" == "true" ]] && run_lint_checks
                [[ "$BUILD_CHECK" == "true" ]] && run_build_checks
            fi
            ;;
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "lint")
            run_lint_checks
            ;;
        "build")
            run_build_checks
            ;;
        *)
            log "ERROR" "Unknown test suite: $SUITE"
            usage
            exit 1
            ;;
    esac

    # Generate final report
    generate_report
}

# Run main function
main "$@"
