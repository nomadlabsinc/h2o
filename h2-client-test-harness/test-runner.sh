#!/bin/sh

# Test runner script for H2 Client Test Harness
# Runs both harness and verifier in Docker environment

set -e

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --test=<test_id>     Run a specific test case"
    echo "  --list               List all available test cases"
    echo "  --harness-only       Run only the harness (for external testing)"
    echo "  --verify-all         Run all tests and verify them"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --test=6.5/1      Run SETTINGS test"
    echo "  $0 --list            List all available tests"
    echo "  $0 --verify-all      Run complete test suite"
}

if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

case "$1" in
    --list)
        echo "Available harness test cases:"
        /h2-client-test-harness
        echo ""
        echo "Available verifier test cases:"
        /h2-verifier
        ;;
    
    --harness-only)
        if [ -z "$2" ]; then
            echo "Error: --harness-only requires a test case"
            echo "Usage: $0 --harness-only --test=<test_id>"
            exit 1
        fi
        echo "Starting harness for test case: ${2#--test=}"
        exec /h2-client-test-harness "$2"
        ;;
    
    --test=*)
        TEST_ID="${1#--test=}"
        echo "Running test case: $TEST_ID"
        echo "Starting harness..."
        
        # Start harness in background
        /h2-client-test-harness --test="$TEST_ID" &
        HARNESS_PID=$!
        
        # Wait for harness to start
        sleep 3
        
        # Run verifier
        echo "Running verifier..."
        if /h2-verifier --test="$TEST_ID"; then
            echo "✅ Test $TEST_ID PASSED"
            RESULT=0
        else
            echo "❌ Test $TEST_ID FAILED"
            RESULT=1
        fi
        
        # Cleanup
        kill $HARNESS_PID 2>/dev/null || true
        wait $HARNESS_PID 2>/dev/null || true
        
        exit $RESULT
        ;;
    
    --verify-all)
        echo "Running complete H2SPEC test suite verification..."
        PASSED=0
        FAILED=0
        
        # Get list of all tests from harness
        TESTS=$(/h2-client-test-harness 2>&1 | grep "  - " | sed 's/  - //')
        
        for test in $TESTS; do
            echo "Testing: $test"
            
            # Start harness in background
            timeout 10s /h2-client-test-harness --test="$test" &
            HARNESS_PID=$!
            
            sleep 2
            
            # Run verifier with timeout
            if timeout 5s /h2-verifier --test="$test" >/dev/null 2>&1; then
                echo "✅ $test PASSED"
                PASSED=$((PASSED + 1))
            else
                echo "❌ $test FAILED"
                FAILED=$((FAILED + 1))
            fi
            
            # Cleanup
            kill $HARNESS_PID 2>/dev/null || true
            wait $HARNESS_PID 2>/dev/null || true
            
            sleep 1
        done
        
        echo ""
        echo "========================================="
        echo "Test Results Summary:"
        echo "PASSED: $PASSED"
        echo "FAILED: $FAILED"
        echo "TOTAL:  $((PASSED + FAILED))"
        echo "SUCCESS RATE: $((PASSED * 100 / (PASSED + FAILED)))%"
        echo "========================================="
        
        if [ $FAILED -eq 0 ]; then
            echo "🎉 All tests passed!"
            exit 0
        else
            echo "💥 Some tests failed"
            exit 1
        fi
        ;;
    
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac