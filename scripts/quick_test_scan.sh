#!/bin/bash

# Quick test scanner - runs tests with shorter timeout and basic categorization

echo "=== UNIT TESTS (spec/h2o/) ==="
echo ""

# Function to run test with timeout
run_with_timeout() {
    local test_file=$1
    local timeout_seconds=$2
    echo -n "Testing $test_file... "
    
    start_time=$(date +%s)
    timeout "$timeout_seconds" docker compose run --rm app crystal spec "$test_file" --no-color > /tmp/test_output.txt 2>&1
    exit_code=$?
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [ $exit_code -eq 124 ]; then
        echo "❌ TIMEOUT (>${timeout_seconds}s)"
        return 1
    elif [ $exit_code -ne 0 ]; then
        echo "❌ FAILED (exit: $exit_code, ${duration}s)"
        return 2
    else
        # Check output for failures
        if grep -q "failures" /tmp/test_output.txt && ! grep -q "0 failures" /tmp/test_output.txt; then
            echo "❌ TEST FAILURES (${duration}s)"
            return 3
        elif [ $duration -gt 5 ]; then
            echo "⚠️  SLOW (${duration}s)"
            return 4
        else
            echo "✅ PASS (${duration}s)"
            return 0
        fi
    fi
}

# Test core unit tests first
echo "Core H2O tests:"
for test in spec/h2o/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 10
done

echo ""
echo "Frame tests:"
for test in spec/h2o/frames/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 10
done

echo ""
echo "HPACK tests:"
for test in spec/h2o/hpack/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 10
done

echo ""
echo "=== OTHER UNIT TESTS ==="
for test in spec/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 10
done

echo ""
echo "=== INTEGRATION TESTS (spec/integration/) ==="
echo "Basic integration tests:"
for test in spec/integration/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 15
done

echo ""
echo "HTTP2 integration tests:"
for test in spec/integration/http2/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 15
done

echo ""
echo "=== COMPLIANCE TESTS (spec/compliance/) ==="
echo "Native H2SPEC tests:"
for test in spec/compliance/native/*_spec.cr; do
    [ -f "$test" ] && run_with_timeout "$test" 15
done