require "./spec_helper"

# Performance benchmarking framework for H2O optimizations
module PerformanceBenchmarks
  # Benchmark result structure
  struct BenchmarkResult
    property name : String
    property iterations : Int32
    property total_time : Time::Span
    property avg_time_per_op : Time::Span
    property memory_allocated : Int64
    property memory_per_op : Int64
    property predicted_improvement : Float64
    property actual_improvement : Float64

    def initialize(@name : String, @iterations : Int32, @total_time : Time::Span,
                   @memory_allocated : Int64, @predicted_improvement : Float64 = 0.0)
      @avg_time_per_op = @total_time / @iterations
      @memory_per_op = @memory_allocated // @iterations
      @actual_improvement = 0.0
    end

    def operations_per_second : Float64
      @iterations.to_f64 / @total_time.total_seconds
    end

    def meets_prediction? : Bool
      @actual_improvement >= (@predicted_improvement * 0.8) # Allow 20% margin
    end
  end

  # Performance comparison between old and new implementations
  class PerformanceComparison
    property baseline : BenchmarkResult
    property optimized : BenchmarkResult
    property improvement_type : String

    def initialize(@baseline : BenchmarkResult, @optimized : BenchmarkResult, @improvement_type : String)
      calculate_improvements
    end

    def time_improvement : Float64
      return 0.0 if @baseline.avg_time_per_op.total_milliseconds == 0.0
      ((@baseline.avg_time_per_op - @optimized.avg_time_per_op) / @baseline.avg_time_per_op) * 100.0
    end

    def memory_improvement : Float64
      return 0.0 if @baseline.memory_per_op == 0
      ((@baseline.memory_per_op - @optimized.memory_per_op).to_f64 / @baseline.memory_per_op.to_f64) * 100.0
    end

    def throughput_improvement : Float64
      return 0.0 if @baseline.operations_per_second == 0.0
      ((@optimized.operations_per_second - @baseline.operations_per_second) / @baseline.operations_per_second) * 100.0
    end

    def summary : String
      String.build do |builder|
        builder << "#{@improvement_type} Performance Comparison:\n"
        builder << "  Baseline: #{@baseline.avg_time_per_op.total_milliseconds.round(3)}ms/op, #{@baseline.memory_per_op} bytes/op\n"
        builder << "  Optimized: #{@optimized.avg_time_per_op.total_milliseconds.round(3)}ms/op, #{@optimized.memory_per_op} bytes/op\n"
        builder << "  Time Improvement: #{time_improvement.round(1)}% (predicted: #{@optimized.predicted_improvement.round(1)}%)\n"
        builder << "  Memory Improvement: #{memory_improvement.round(1)}%\n"
        builder << "  Throughput Improvement: #{throughput_improvement.round(1)}%\n"
        builder << "  Prediction Met: #{meets_prediction?}\n"
      end
    end

    def meets_prediction? : Bool
      case @improvement_type.downcase
      when "time", "latency"
        time_improvement >= (@optimized.predicted_improvement * 0.8)
      when "memory"
        memory_improvement >= (@optimized.predicted_improvement * 0.8)
      when "throughput"
        throughput_improvement >= (@optimized.predicted_improvement * 0.8)
      else
        # Default to time improvement
        time_improvement >= (@optimized.predicted_improvement * 0.8)
      end
    end

    private def calculate_improvements
      @optimized.actual_improvement = case @improvement_type.downcase
                                      when "time", "latency"
                                        time_improvement
                                      when "memory"
                                        memory_improvement
                                      when "throughput"
                                        throughput_improvement
                                      else
                                        time_improvement
                                      end
    end
  end

  # Generic benchmark runner
  class BenchmarkRunner
    def self.measure(name : String, iterations : Int32 = 1000, predicted_improvement : Float64 = 0.0, &block : -> Nil) : BenchmarkResult
      # Force garbage collection before benchmark
      GC.collect

      # Measure memory before
      memory_before = GC.stats.heap_size

      start_time = Time.monotonic

      iterations.times do |_|
        block.call
      end

      end_time = Time.monotonic

      # Measure memory after
      memory_after = GC.stats.heap_size
      memory_allocated = Math.max(0_i64, (memory_after - memory_before).to_i64)

      total_time = end_time - start_time

      BenchmarkResult.new(
        name: name,
        iterations: iterations,
        total_time: total_time,
        memory_allocated: memory_allocated,
        predicted_improvement: predicted_improvement
      )
    end

    def self.compare(baseline_name : String, optimized_name : String, improvement_type : String,
                     iterations : Int32, predicted_improvement : Float64,
                     baseline_block : Proc(Nil), optimized_block : Proc(Nil)) : PerformanceComparison
      puts "Running baseline benchmark: #{baseline_name}..."
      baseline = measure(baseline_name, iterations) { baseline_block.call }

      puts "Running optimized benchmark: #{optimized_name}..."
      optimized = measure(optimized_name, iterations, predicted_improvement) { optimized_block.call }

      PerformanceComparison.new(baseline, optimized, improvement_type)
    end
  end

  # Memory allocation tracker
  class AllocationTracker
    @@allocations = Atomic(Int64).new(0)
    @@deallocations = Atomic(Int64).new(0)

    def self.reset : Nil
      @@allocations.set(0)
      @@deallocations.set(0)
    end

    def self.track_allocation(size : Int32) : Nil
      @@allocations.add(size.to_i64)
    end

    def self.track_deallocation(size : Int32) : Nil
      @@deallocations.add(size.to_i64)
    end

    def self.net_allocations : Int64
      @@allocations.get - @@deallocations.get
    end

    def self.total_allocations : Int64
      @@allocations.get
    end
  end
end

describe "Performance Benchmarks" do
  it "should have working benchmark framework" do
    result = PerformanceBenchmarks::BenchmarkRunner.measure("test", 100) do
      # Simple operation
      String.build do |builder|
        builder << "test"
      end
    end

    result.name.should eq("test")
    result.iterations.should eq(100)
    result.total_time.should be > Time::Span.zero
    result.operations_per_second.should be > 0.0
  end

  it "should correctly compare baseline vs optimized" do
    # Baseline: Inefficient string concatenation
    baseline_op = -> {
      s = ""
      100.times { s += "a" }
    }

    # Optimized: Efficient string building
    optimized_op = -> {
      String.build do |str|
        100.times { str << "a" }
      end
    }

    comparison = PerformanceBenchmarks::BenchmarkRunner.compare(
      "String Concat", "String Build", "time", 1000, 50.0,
      baseline_op,
      optimized_op
    )

    comparison.time_improvement.should be > 30.0 # Expect a significant improvement
    comparison.meets_prediction?.should be_true
  end
end
