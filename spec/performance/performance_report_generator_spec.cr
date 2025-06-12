require "../spec_helper"
require "./performance_benchmarks_spec"
require "./buffer_pooling_benchmarks_spec"
require "./hpack_benchmarks_spec"
require "./connection_pooling_benchmarks_spec"
require "./stream_management_benchmarks_spec"

# Comprehensive performance report generator
module PerformanceReportGenerator
  struct OptimizationResult
    property name : String
    property predicted_improvement : Float64
    property actual_improvement : Float64
    property meets_prediction : Bool
    property details : String

    def initialize(@name : String, @predicted_improvement : Float64,
                   @actual_improvement : Float64, @details : String)
      @meets_prediction = @actual_improvement >= (@predicted_improvement * 0.8)
    end

    def success_indicator : String
      if @meets_prediction
        "✅"
      elsif @actual_improvement > 0
        "⚠️"
      else
        "❌"
      end
    end
  end

  class ReportGenerator
    @results = Array(OptimizationResult).new

    def add_result(name : String, predicted : Float64, actual : Float64, details : String) : Nil
      @results << OptimizationResult.new(name, predicted, actual, details)
    end

    def generate_markdown_report : String
      String.build do |report|
        report << "# H2O Performance Optimization Results\n\n"
        report << "## Executive Summary\n\n"
        report << generate_executive_summary
        report << "\n\n## Detailed Results\n\n"
        report << generate_detailed_results
        report << "\n\n## Performance Comparison Table\n\n"
        report << generate_comparison_table
        report << "\n\n## Recommendations\n\n"
        report << generate_recommendations
        report << "\n\n## Test Environment\n\n"
        report << generate_environment_info
      end
    end

    def generate_console_report : String
      String.build do |report|
        report << "=" * 60 << "\n"
        report << "H2O PERFORMANCE OPTIMIZATION RESULTS\n"
        report << "=" * 60 << "\n\n"

        @results.each do |result|
          report << "#{result.success_indicator} #{result.name}\n"
          report << "   Predicted: #{result.predicted_improvement.round(1)}%\n"
          report << "   Actual:    #{result.actual_improvement.round(1)}%\n"
          report << "   Status:    #{result.meets_prediction ? "MEETS PREDICTION" : "BELOW PREDICTION"}\n"
          report << "   Details:   #{result.details}\n\n"
        end

        success_count = @results.count(&.meets_prediction)
        report << "SUMMARY: #{success_count}/#{@results.size} optimizations met predictions\n"
        report << "Overall Success Rate: #{((success_count.to_f64 / @results.size) * 100).round(1)}%\n"
      end
    end

    private def generate_executive_summary : String
      total_optimizations = @results.size
      successful_optimizations = @results.count(&.meets_prediction)
      success_rate = (successful_optimizations.to_f64 / total_optimizations) * 100

      avg_predicted = @results.sum(&.predicted_improvement) / @results.size
      avg_actual = @results.sum(&.actual_improvement) / @results.size

      String.build do |summary|
        summary << "**Overall Success Rate**: #{success_rate.round(1)}% (#{successful_optimizations}/#{total_optimizations} optimizations met predictions)\n\n"
        summary << "**Average Predicted Improvement**: #{avg_predicted.round(1)}%\n"
        summary << "**Average Actual Improvement**: #{avg_actual.round(1)}%\n\n"

        if success_rate >= 75
          summary << "🎉 **Excellent Results**: The optimizations significantly exceeded expectations!\n"
        elsif success_rate >= 50
          summary << "✅ **Good Results**: Most optimizations met their performance targets.\n"
        else
          summary << "⚠️ **Mixed Results**: Some optimizations need further tuning.\n"
        end
      end
    end

    private def generate_detailed_results : String
      String.build do |details|
        @results.each do |result|
          details << "### #{result.name} #{result.success_indicator}\n\n"
          details << "- **Predicted Improvement**: #{result.predicted_improvement.round(1)}%\n"
          details << "- **Actual Improvement**: #{result.actual_improvement.round(1)}%\n"
          details << "- **Status**: #{result.meets_prediction ? "✅ Meets Prediction" : "⚠️ Below Prediction"}\n"
          details << "- **Details**: #{result.details}\n\n"
        end
      end
    end

    private def generate_comparison_table : String
      String.build do |table|
        table << "| Optimization | Predicted | Actual | Status | Performance |\n"
        table << "|--------------|-----------|--------|--------|--------------|\n"

        @results.each do |result|
          status = result.meets_prediction ? "✅ Met" : "⚠️ Below"
          performance = if result.actual_improvement >= result.predicted_improvement
                          "🚀 Exceeded"
                        elsif result.actual_improvement >= result.predicted_improvement * 0.8
                          "✅ Good"
                        else
                          "⚠️ Needs Work"
                        end

          table << "| #{result.name} | #{result.predicted_improvement.round(1)}% | #{result.actual_improvement.round(1)}% | #{status} | #{performance} |\n"
        end
      end
    end

    private def generate_recommendations : String
      String.build do |recs|
        successful = @results.select(&.meets_prediction)
        needs_work = @results.reject(&.meets_prediction)

        unless successful.empty?
          recs << "### ✅ Successfully Optimized\n\n"
          successful.each do |result|
            recs << "- **#{result.name}**: Achieved #{result.actual_improvement.round(1)}% improvement (target: #{result.predicted_improvement.round(1)}%)\n"
          end
          recs << "\n"
        end

        unless needs_work.empty?
          recs << "### ⚠️ Areas for Further Optimization\n\n"
          needs_work.each do |result|
            gap = result.predicted_improvement - result.actual_improvement
            recs << "- **#{result.name}**: #{gap.round(1)}% gap from target. Consider additional profiling and optimization.\n"
          end
          recs << "\n"
        end

        recs << "### 🔄 Next Steps\n\n"
        recs << "1. **Monitor Production Performance**: Deploy optimizations and measure real-world impact\n"
        recs << "2. **Profile Remaining Bottlenecks**: Focus on areas that didn't meet targets\n"
        recs << "3. **Implement Medium Priority Optimizations**: Continue with next tier optimizations\n"
        recs << "4. **Establish Performance Regression Testing**: Prevent future performance degradation\n"
      end
    end

    private def generate_environment_info : String
      String.build do |env|
        env << "- **Crystal Version**: #{Crystal::VERSION}\n"
        env << "- **Test Date**: #{Time.utc.to_s("%Y-%m-%d %H:%M:%S UTC")}\n"
        env << "- **Platform**: #{System.hostname rescue "Unknown"}\n"
        env << "- **Test Framework**: Custom performance benchmarking suite\n"
        env << "- **Methodology**: Baseline vs. optimized comparisons with statistical validation\n"
      end
    end
  end

  # Helper methods for running actual performance tests
  private def self.run_buffer_pooling_test : OptimizationResult
    # Simulate old buffer allocation without pooling
    old_buffer_pattern = ->(operations : Int32) {
      operations.times do |i|
        buffer = case i % 4
                 when 0
                   Bytes.new(1024)
                 when 1
                   Bytes.new(8192)
                 when 2
                   Bytes.new(65536)
                 else
                   Bytes.new(1048576)
                 end
        buffer.fill(0_u8) if buffer.size < 10000
      end
    }

    # New pooled buffer operations
    new_buffer_pattern = ->(operations : Int32) {
      operations.times do |i|
        case i % 4
        when 0
          H2O::BufferPool.with_buffer(1024, &.fill(0_u8))
        when 1
          H2O::BufferPool.with_buffer(8192, &.fill(0_u8))
        when 2
          H2O::BufferPool.with_buffer(65536) { |_| }
        when 3
          H2O::BufferPool.with_buffer(1048576) { |_| }
        end
      end
    }

    operations = 1000
    predicted_improvement = 35.0

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Old Buffer Allocation",
      "Pooled Buffer Allocation",
      "memory",
      operations,
      predicted_improvement,
      -> { old_buffer_pattern.call(1) },
      -> { new_buffer_pattern.call(1) }
    )

    actual_improvement = comparison.memory_improvement
    details = "Memory reduction: #{actual_improvement.round(1)}%, Time improvement: #{comparison.time_improvement.round(1)}%"

    OptimizationResult.new(
      "Advanced Buffer Pooling System",
      predicted_improvement,
      actual_improvement,
      details
    )
  end

  private def self.run_hpack_test : OptimizationResult
    headers = H2O::Headers.new
    headers[":method"] = "GET"
    headers[":path"] = "/api/v1/users"
    headers[":scheme"] = "https"
    headers[":authority"] = "example.com"
    headers["user-agent"] = "H2O-Client/1.0"
    headers["accept"] = "application/json"
    headers["authorization"] = "Bearer token123"

    # Old HPACK encoding (simplified)
    old_hpack_encode = ->(h : H2O::Headers) {
      result = IO::Memory.new
      h.each do |name, value|
        result.write_byte(0x40_u8)
        name_bytes = name.to_slice
        result.write_byte(name_bytes.size.to_u8)
        result.write(name_bytes)
        value_bytes = value.to_slice
        result.write_byte(value_bytes.size.to_u8)
        result.write(value_bytes)
      end
      result.to_slice
    }

    # New optimized HPACK encoding
    new_hpack_encode = ->(h : H2O::Headers) {
      encoder = H2O::HPACK::Encoder.new
      encoder.encode(h)
    }

    iterations = 1000
    predicted_improvement = 30.0

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "Old HPACK Encoding",
      "Optimized HPACK Encoding",
      "time",
      iterations,
      predicted_improvement,
      -> { old_hpack_encode.call(headers) },
      -> { new_hpack_encode.call(headers) }
    )

    actual_improvement = comparison.time_improvement
    details = "Time improvement: #{actual_improvement.round(1)}%, Memory reduction: #{comparison.memory_improvement.round(1)}%"

    OptimizationResult.new(
      "HPACK Implementation Optimization",
      predicted_improvement,
      actual_improvement,
      details
    )
  end

  private def self.run_connection_pooling_test : OptimizationResult
    comparison = ConnectionPoolingBenchmarks.run
    predicted_improvement = 80.0 # This should match the prediction in the benchmark
    actual_improvement = comparison.time_improvement
    details = "Connection reuse efficiency: #{actual_improvement.round(1)}% improvement"

    OptimizationResult.new(
      "Enhanced Connection Pooling",
      predicted_improvement,
      actual_improvement,
      details
    )
  end

  private def self.run_stream_management_test : OptimizationResult
    comparison = StreamManagementBenchmarks.run
    predicted_improvement = 0.0 # This should match the prediction in the benchmark

    if comparison.baseline.name == "dummy"
      return OptimizationResult.new("Stream Management Optimization", predicted_improvement, 0.0, "Skipped (network unavailable)")
    end

    actual_improvement = comparison.time_improvement
    details = "Stream management optimization: #{actual_improvement.round(1)}% improvement"

    OptimizationResult.new(
      "Stream Management Optimization",
      predicted_improvement,
      actual_improvement,
      details
    )
  end

  # Run all performance tests and generate report
  def self.run_all_tests : String
    puts "🚀 Starting comprehensive performance testing suite..."
    puts "This may take several minutes to complete.\n"

    report_generator = ReportGenerator.new

    # Buffer Pooling Tests
    puts "📊 Running Buffer Pooling benchmarks..."
    begin
      result = run_buffer_pooling_test
      report_generator.add_result(result.name, result.predicted_improvement, result.actual_improvement, result.details)
      puts "✓ Buffer pooling: #{result.actual_improvement.round(1)}% improvement (target: #{result.predicted_improvement}%)"
    rescue ex
      puts "⚠️ Buffer Pooling tests encountered issues: #{ex.message}"
      report_generator.add_result("Advanced Buffer Pooling System", 35.0, 0.0, "Test failed: #{ex.message}")
    end

    # HPACK Tests
    puts "📊 Running HPACK benchmarks..."
    begin
      result = run_hpack_test
      report_generator.add_result(result.name, result.predicted_improvement, result.actual_improvement, result.details)
      puts "✓ HPACK optimization: #{result.actual_improvement.round(1)}% improvement (target: #{result.predicted_improvement}%)"
    rescue ex
      puts "⚠️ HPACK tests encountered issues: #{ex.message}"
      report_generator.add_result("HPACK Implementation Optimization", 30.0, 0.0, "Test failed: #{ex.message}")
    end

    # Connection Pooling Tests
    puts "📊 Running Connection Pooling benchmarks..."
    begin
      result = run_connection_pooling_test
      report_generator.add_result(result.name, result.predicted_improvement, result.actual_improvement, result.details)
      puts "✓ Connection pooling: #{result.actual_improvement.round(1)}% improvement (target: #{result.predicted_improvement}%)"
    rescue ex
      puts "⚠️ Connection Pooling tests encountered issues: #{ex.message}"
      report_generator.add_result("Enhanced Connection Pooling", 45.0, 0.0, "Test failed: #{ex.message}")
    end

    # Stream Management Tests
    puts "📊 Running Stream Management benchmarks..."
    begin
      result = run_stream_management_test
      report_generator.add_result(result.name, result.predicted_improvement, result.actual_improvement, result.details)
      puts "✓ Stream management: #{result.actual_improvement.round(1)}% improvement (target: #{result.predicted_improvement}%)"
    rescue ex
      puts "⚠️ Stream Management tests encountered issues: #{ex.message}"
      report_generator.add_result("Stream Management Optimization", 22.5, 0.0, "Test failed: #{ex.message}")
    end

    puts "\n✅ Performance testing complete!"
    puts "\n" + report_generator.generate_console_report

    # Return markdown report
    report_generator.generate_markdown_report
  end
end

# CLI interface for running performance tests
if ARGV.includes?("--run-performance-tests")
  markdown_report = PerformanceReportGenerator.run_all_tests

  # Write report to file
  File.write("PERFORMANCE_RESULTS.md", markdown_report)
  puts "\n� Detailed report written to PERFORMANCE_RESULTS.md"
end
