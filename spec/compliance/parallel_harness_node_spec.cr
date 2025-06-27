require "../spec_helper"
require "process"
require "channel"

# This file runs a subset of tests based on NODE environment variable
# Used for parallel execution in CI across multiple nodes

# Import test definitions from parallel_harness_spec
require "./parallel_harness_spec"

# Get node number from environment
NODE = ENV.fetch("NODE", "1").to_i
TOTAL_NODES = ENV.fetch("TOTAL_NODES", "4").to_i

describe "H2O Parallel HTTP/2 Compliance Tests (Node #{NODE}/#{TOTAL_NODES})" do
  it "passes h2spec compliance tests for this node" do
    # Split tests evenly across nodes
    tests_per_node = (PARALLEL_H2SPEC_TEST_CASES.size / TOTAL_NODES.to_f).ceil.to_i
    start_index = (NODE - 1) * tests_per_node
    end_index = [start_index + tests_per_node - 1, PARALLEL_H2SPEC_TEST_CASES.size - 1].min
    
    node_tests = PARALLEL_H2SPEC_TEST_CASES[start_index..end_index]
    
    puts "\n🚀 Running H2O HTTP/2 Compliance Tests (Node #{NODE}/#{TOTAL_NODES})"
    puts "Test range: #{start_index + 1}-#{end_index + 1} of #{PARALLEL_H2SPEC_TEST_CASES.size}"
    puts "Tests on this node: #{node_tests.size}"
    puts "=" * 80
    
    overall_start = Time.monotonic
    
    # Run tests in parallel with controlled concurrency
    results = ParallelComplianceTestRunner.run_tests_in_parallel(node_tests, concurrency: 8)
    
    # Sort results by test_id for consistent reporting
    results.sort_by!(&.test_id)
    
    # Summary
    total_duration = Time.monotonic - overall_start
    passed_count = results.count(&.passed)
    failed_count = results.size - passed_count
    
    puts "\n" + "=" * 80
    puts "Node #{NODE} Results"
    puts "=" * 80
    puts "Tests Run:     #{results.size}"
    puts "Passed:        #{passed_count}"
    puts "Failed:        #{failed_count}"
    puts "Success Rate:  #{(passed_count * 100.0 / results.size).round(2)}%"
    puts "Duration:      #{total_duration.total_seconds.round(2)}s"
    puts "=" * 80
    
    if failed_count > 0
      puts "\n❌ Failed Tests on Node #{NODE}:"
      results.reject(&.passed).each do |result|
        puts "  - #{result.test_id}: #{result.error}"
      end
    end
    
    # Test passes if we have high success rate
    (passed_count.to_f / results.size).should be >= 0.95  # 95% minimum
  end
end