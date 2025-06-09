require "../spec_helper"
require "../../src/h2o/client"
require "../performance_benchmarks_spec"

module StreamManagementBenchmarks
  def self.run : PerformanceBenchmarks::PerformanceComparison
    # Use a real server to test stream lifecycle
    # Baseline: Simple GET requests
    baseline_op = -> {
      client = H2O::Client.new
      client.get("http://httpbin.org/get")
      client.close
    }

    # Optimized: Could involve client-side optimizations for stream reuse/management
    # For now, we'll compare against a slightly more complex request
    optimized_op = -> {
      client = H2O::Client.new
      headers = H2O::Headers.new
      headers["X-Test"] = "true"
      client.get("http://httpbin.org/get", headers: headers)
      client.close
    }

    iterations = 10
    predicted_improvement = 0.0 # Expect similar performance for now

    # Skip if network tests are disabled
    unless NetworkTestHelper.require_network("Stream Management Benchmark") { true }
      # Return a dummy comparison if network is unavailable
      return PerformanceBenchmarks::PerformanceComparison.new(
        PerformanceBenchmarks::BenchmarkResult.new("dummy", 0, 0.seconds, 0),
        PerformanceBenchmarks::BenchmarkResult.new("dummy", 0, 0.seconds, 0),
        "time"
      )
    end

    PerformanceBenchmarks::BenchmarkRunner.compare(
      "Simple GET Stream",
      "GET Stream with Headers",
      "time",
      iterations,
      predicted_improvement,
      baseline_op,
      optimized_op
    )
  end
end
