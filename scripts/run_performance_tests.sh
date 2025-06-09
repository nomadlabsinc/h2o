#!/bin/bash

# H2O Performance Testing Script
# Runs comprehensive performance benchmarks and generates reports

set -e

echo "🚀 H2O Performance Testing Suite"
echo "================================="
echo

# Check if Crystal is available
if ! command -v crystal &> /dev/null; then
    echo "❌ Error: Crystal compiler not found"
    echo "Please install Crystal: https://crystal-lang.org/install/"
    exit 1
fi

echo "📋 Environment Information"
echo "Crystal Version: $(crystal --version | head -n1)"
echo "Platform: $(uname -s)"
echo "Date: $(date)"
echo

# Run benchmarking framework tests first
echo "🧪 Testing benchmarking framework..."
if crystal spec spec/performance_benchmarks.cr --no-color; then
    echo "✅ Benchmarking framework tests passed"
else
    echo "❌ Benchmarking framework tests failed"
    exit 1
fi
echo

# Run individual performance test suites
test_suites=(
    "spec/performance/buffer_pooling_benchmarks_spec.cr"
    "spec/performance/hpack_benchmarks_spec.cr"
    "spec/performance/connection_pooling_benchmarks_spec.cr"
    "spec/performance/stream_management_benchmarks_spec.cr"
)

echo "📊 Running performance benchmarks..."
echo "This may take several minutes to complete."
echo

failed_tests=0
for suite in "${test_suites[@]}"; do
    suite_name=$(basename "$suite" .cr)
    echo "Running $suite_name..."

    if timeout 300s crystal spec "$suite" --no-color 2>/dev/null; then
        echo "✅ $suite_name completed successfully"
    else
        echo "⚠️ $suite_name encountered issues (timeout or errors)"
        ((failed_tests++))
    fi
    echo
done

# Generate performance report
echo "📄 Generating performance report..."
if crystal run spec/performance_report_generator.cr -- --run-performance-tests; then
    echo "✅ Performance report generated: PERFORMANCE_RESULTS.md"
else
    echo "⚠️ Performance report generation had issues"
fi
echo

# Summary
echo "📋 Testing Summary"
echo "=================="
echo "Total test suites: ${#test_suites[@]}"
echo "Failed/problematic: $failed_tests"
echo "Success rate: $(( (${#test_suites[@]} - failed_tests) * 100 / ${#test_suites[@]} ))%"
echo

if [ $failed_tests -eq 0 ]; then
    echo "🎉 All performance tests completed successfully!"
    echo "📖 Review PERFORMANCE_RESULTS.md for detailed analysis"
else
    echo "⚠️ Some tests had issues - this is normal for performance testing"
    echo "📖 Check PERFORMANCE_RESULTS.md for available results"
fi

echo
echo "💡 Tips:"
echo "  - Performance results may vary based on system load"
echo "  - Run tests multiple times for consistent measurements"
echo "  - Use 'crystal build --release' for production performance"
echo
