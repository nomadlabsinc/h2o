#!/usr/bin/env crystal

# Parallel test orchestrator for maximum test suite performance
require "process"
require "fiber"
require "channel"

# Test category definitions
UNIT_TESTS = [
  "spec/h2o/frames/",
  "spec/h2o/hpack/",
  "spec/h2o/*_spec.cr",
]

INTEGRATION_TESTS = [
  "spec/integration/ultra_fast_integration_spec.cr",
  "spec/integration/massively_parallel_spec.cr",
  "spec/integration/comprehensive_http2_validation_spec.cr",
]

REGRESSION_TESTS = [
  "spec/integration/http2_protocol_compliance_spec.cr",
  "spec/integration/regression_prevention_spec.cr",
]

class ParallelTestOrchestrator
  def self.run_all_tests_in_parallel
    puts "🚀 Starting massively parallel test execution..."
    start_time = Time.monotonic

    # Ensure Docker services are running
    ensure_docker_services

    # Run different test categories in parallel
    channels = Array(Channel({String, Bool, Time::Span})).new

    # Unit tests (fast, no network)
    spawn_test_category("Unit Tests", UNIT_TESTS, channels)

    # Integration tests (local network)
    spawn_test_category("Integration Tests", INTEGRATION_TESTS, channels)

    # Regression tests (local network)
    spawn_test_category("Regression Tests", REGRESSION_TESTS, channels)

    # Collect results
    results = channels.map(&.receive)

    total_elapsed = Time.monotonic - start_time

    # Print summary
    puts "\n" + "="*80
    puts "🎯 PARALLEL TEST EXECUTION SUMMARY"
    puts "="*80

    results.each do |(category, success, elapsed)|
      status = success ? "✅ PASSED" : "❌ FAILED"
      puts "#{category.ljust(20)} #{status} in #{elapsed.total_seconds.round(2)}s"
    end

    total_passed = results.count(&.[1])
    overall_success = total_passed == results.size

    puts "-"*80
    puts "Overall: #{total_passed}/#{results.size} categories passed"
    puts "Total time: #{total_elapsed.total_seconds.round(2)}s"
    puts "Status: #{overall_success ? "✅ ALL TESTS PASSED" : "❌ SOME TESTS FAILED"}"
    puts "="*80

    exit(overall_success ? 0 : 1)
  end

  private def self.spawn_test_category(category : String, test_paths : Array(String), channels : Array(Channel({String, Bool, Time::Span})))
    channel = Channel({String, Bool, Time::Span}).new(1)
    channels << channel

    spawn do
      puts "🏃 Starting #{category}..."
      start_time = Time.monotonic

      success = run_test_category(test_paths)
      elapsed = Time.monotonic - start_time

      status = success ? "✅" : "❌"
      puts "#{status} #{category} completed in #{elapsed.total_seconds.round(2)}s"

      channel.send({category, success, elapsed})
    end
  end

  def self.run_test_category(test_paths : Array(String)) : Bool
    # Run crystal spec with all test paths
    cmd_parts = ["crystal", "spec"] + test_paths + ["--progress"]

    process = Process.run(
      cmd_parts[0],
      cmd_parts[1..],
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit
    )

    process.success?
  end

  def self.ensure_docker_services
    puts "🐳 Ensuring Docker services are running..."

    # Check if services are already running
    result = Process.run("docker", ["compose", "ps", "-q"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe,
      chdir: "spec/integration")

    if result.success? && !result.output.to_s.strip.empty?
      puts "✅ Docker services already running"
      return
    end

    # Start services
    start_result = Process.run("docker", ["compose", "up", "-d"],
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit,
      chdir: "spec/integration")

    if start_result.success?
      puts "✅ Docker services started"

      # Wait for services to be ready
      sleep(2.seconds)
    else
      puts "❌ Failed to start Docker services"
      exit(1)
    end
  end
end

# Enhanced parallel execution with resource optimization
class OptimizedTestRunner
  def self.run_with_resource_optimization
    puts "⚡ Running optimized parallel test execution..."
    start_time = Time.monotonic

    # Ensure optimal environment
    optimize_environment

    # Run tests with maximum parallelization
    result = run_parallel_categories

    total_elapsed = Time.monotonic - start_time
    puts "🏁 Optimized execution completed in #{total_elapsed.total_seconds.round(2)}s"

    result
  end

  private def self.optimize_environment
    # Ensure Docker services are running
    ensure_docker_services

    # Pre-warm connections (optional)
    puts "🔥 Pre-warming test environment..."

    # Quick connectivity test
    test_result = Process.run("curl", ["-k", "-s", "https://localhost:8443/"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe)

    if test_result.success?
      puts "✅ Test servers are responsive"
    else
      puts "⚠️  Test servers may be slow to respond"
    end
  end

  private def self.run_parallel_categories : nBool
    categories = [
      {"Fast Unit Tests", ["spec/h2o/frames/", "spec/h2o/hpack/"]},
      {"Core Unit Tests", ["spec/h2o/timeout_spec.cr", "spec/h2o/circuit_breaker_spec.cr"]},
      {"Ultra-Fast Integration", ["spec/integration/ultra_fast_integration_spec.cr"]},
      {"Parallel Integration", ["spec/integration/massively_parallel_spec.cr"]},
      {"Comprehensive Integration", ["spec/integration/comprehensive_http2_validation_spec.cr"]},
    ]

    channels = Array(Channel(Bool)).new(categories.size)

    categories.each do |(name, paths)|
      channel = Channel(Bool).new(1)
      channels << channel

      spawn do
        puts "🏃 Running #{name}..."
        success = run_test_category(paths)
        puts "#{success ? "✅" : "❌"} #{name} completed"
        channel.send(success)
      end
    end

    # Wait for all categories to complete
    results = channels.map(&.receive)
    successful_count = results.count(&.itself)

    puts "📊 Results: #{successful_count}/#{categories.size} categories passed"

    successful_count == categories.size
  end
end

# Command-line interface
case ARGV[0]?
when "optimized"
  OptimizedTestRunner.run_with_resource_optimization
when "standard"
  ParallelTestOrchestrator.run_all_tests_in_parallel
else
  puts "Usage: #{PROGRAM_NAME} [optimized|standard]"
  puts ""
  puts "optimized: Maximum parallelization with resource optimization"
  puts "standard:  Standard parallel execution across test categories"
  exit(1)
end
