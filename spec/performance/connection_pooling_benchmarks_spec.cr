require "../spec_helper"
require "../support/http11_server"
require "../../src/h2o/client"
require "../performance_benchmarks_spec"

module ConnectionPoolingBenchmarks
  def self.run : PerformanceBenchmarks::PerformanceComparison
    server = TestSupport::Http11Server.new(0, ssl: false)
    server.start
    port = server.port

    # Baseline: Create a new client for each request
    baseline_op = -> {
      client = H2O::Client.new
      client.get("http://127.0.0.1:#{port}/")
      client.close
    }

    # Optimized: Reuse a single client with connection pooling
    reused_client = H2O::Client.new
    optimized_op = -> {
      reused_client.get("http://127.0.0.1:#{port}/")
    }

    iterations = 20
    predicted_improvement = 80.0

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "New Client Per Request",
      "Reused Client (Pooling)",
      "time",
      iterations,
      predicted_improvement,
      baseline_op,
      optimized_op
    )

    reused_client.close
    server.stop

    comparison
  end
end
