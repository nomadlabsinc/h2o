#!/bin/bash

# Test categorizer script
# This script runs all test files and categorizes them

OUTPUT_DIR="test-results"
mkdir -p "$OUTPUT_DIR"

# Clear previous results
rm -f "$OUTPUT_DIR"/*.txt

# Function to run a single test file
run_test() {
    local test_file=$1
    local basename=$(basename "$test_file" .cr)
    local output_file="$OUTPUT_DIR/${basename}.out"
    local timing_file="$OUTPUT_DIR/${basename}.time"
    
    echo "Running: $test_file"
    
    # Run test with timeout and capture output
    start_time=$(date +%s.%N)
    timeout 30 docker compose run --rm app crystal spec "$test_file" --no-color > "$output_file" 2>&1
    exit_code=$?
    end_time=$(date +%s.%N)
    
    # Calculate duration
    duration=$(echo "$end_time - $start_time" | bc)
    echo "$duration" > "$timing_file"
    
    # Categorize result
    if [ $exit_code -eq 124 ]; then
        echo "$test_file" >> "$OUTPUT_DIR/timeouts.txt"
        echo "  ❌ TIMEOUT (30s)"
    elif [ $exit_code -ne 0 ]; then
        echo "$test_file" >> "$OUTPUT_DIR/failures.txt"
        echo "  ❌ FAILED (exit code: $exit_code)"
    else
        # Check for failures in output
        if grep -q "failures" "$output_file" && ! grep -q "0 failures" "$output_file"; then
            echo "$test_file" >> "$OUTPUT_DIR/failures.txt"
            echo "  ❌ FAILED (test failures)"
        elif (( $(echo "$duration > 10" | bc -l) )); then
            echo "$test_file" >> "$OUTPUT_DIR/slow.txt"
            echo "  ⚠️  SLOW (${duration}s)"
        else
            echo "$test_file" >> "$OUTPUT_DIR/passed.txt"
            echo "  ✅ PASSED (${duration}s)"
        fi
    fi
}

# Find all test files
echo "Finding test files..."
find spec -name "*_spec.cr" -type f | sort > "$OUTPUT_DIR/all_tests.txt"

# Run each test
while IFS= read -r test_file; do
    run_test "$test_file"
done < "$OUTPUT_DIR/all_tests.txt"

echo ""
echo "=== TEST SUMMARY ==="
echo ""

# Display results
if [ -f "$OUTPUT_DIR/timeouts.txt" ]; then
    echo "❌ TIMEOUTS:"
    cat "$OUTPUT_DIR/timeouts.txt"
    echo ""
fi

if [ -f "$OUTPUT_DIR/failures.txt" ]; then
    echo "❌ FAILURES:"
    cat "$OUTPUT_DIR/failures.txt"
    echo ""
fi

if [ -f "$OUTPUT_DIR/slow.txt" ]; then
    echo "⚠️  SLOW TESTS (>10s):"
    cat "$OUTPUT_DIR/slow.txt"
    echo ""
fi

# Count totals
total=$(wc -l < "$OUTPUT_DIR/all_tests.txt")
passed=$([ -f "$OUTPUT_DIR/passed.txt" ] && wc -l < "$OUTPUT_DIR/passed.txt" || echo 0)
failed=$([ -f "$OUTPUT_DIR/failures.txt" ] && wc -l < "$OUTPUT_DIR/failures.txt" || echo 0)
timeout=$([ -f "$OUTPUT_DIR/timeouts.txt" ] && wc -l < "$OUTPUT_DIR/timeouts.txt" || echo 0)
slow=$([ -f "$OUTPUT_DIR/slow.txt" ] && wc -l < "$OUTPUT_DIR/slow.txt" || echo 0)

echo "📊 TOTALS:"
echo "  Total tests: $total"
echo "  Passed: $passed"
echo "  Failed: $failed"
echo "  Timeouts: $timeout"
echo "  Slow: $slow"