# Composable Fuzzing Framework for Crystal
# Designed to be extracted as a standalone shard in the future
# Architecture supports pluggable fuzzing backends

module Crystal::Fuzzing
  # Abstract base fuzzer interface
  # Designed to accommodate multiple fuzzing backends (native Crystal, external tools, etc.)
  abstract class Fuzzer
    # Core fuzzing interface
    abstract def fuzz(target : FuzzTarget, iterations : Int32) : FuzzResult
    
    # Configure fuzzing parameters
    def configure(config : FuzzConfig) : Nil
      # Default implementation - override if needed
    end
  end
  
  # Fuzzing target interface - what gets fuzzed
  abstract class FuzzTarget
    property name : String
    
    def initialize(@name : String)
    end
    
    # Execute one fuzzing iteration with given input
    # Should return :success, :expected_error, or :crash
    abstract def execute(input : Bytes) : FuzzOutcome
    
    # Generate seed inputs for corpus-based fuzzing
    def seed_inputs : Array(Bytes)
      [] of Bytes
    end
    
    # Validate that a crash is reproducible
    def reproduce_crash(input : Bytes) : Bool
      execute(input) == FuzzOutcome::Crash
    end
  end
  
  # Fuzzing outcome for each iteration
  enum FuzzOutcome
    Success       # Input processed successfully
    ExpectedError # Input caused expected exception/error
    Crash         # Unexpected crash or unhandled error
  end
  
  # Fuzzing configuration
  struct FuzzConfig
    property seed : UInt32?
    property max_input_size : Int32
    property mutation_strategy : MutationStrategy
    property timeout_ms : Int32
    
    def initialize(@seed = nil, @max_input_size = 1024, @mutation_strategy = MutationStrategy::Random, @timeout_ms = 1000)
    end
  end
  
  # Input mutation strategies
  enum MutationStrategy
    Random      # Completely random inputs
    Mutational  # Mutate from seed corpus
    Generative  # Generate structured inputs
    Hybrid      # Combine multiple strategies
  end
  
  # Fuzzing results and statistics
  struct FuzzResult
    property target_name : String
    property iterations : Int32
    property successes : Int32
    property expected_errors : Int32
    property crashes : Int32
    property timeouts : Int32
    property duration : Time::Span
    property crash_inputs : Array(Bytes)
    
    def initialize(@target_name : String)
      @iterations = 0
      @successes = 0
      @expected_errors = 0
      @crashes = 0
      @timeouts = 0
      @duration = Time::Span.zero
      @crash_inputs = [] of Bytes
    end
    
    def crash_rate : Float64
      @crashes.to_f / @iterations
    end
    
    def error_rate : Float64
      @expected_errors.to_f / @iterations
    end
    
    def success_rate : Float64
      @successes.to_f / @iterations
    end
    
    def summary : String
      String.build do |str|
        str << "Fuzzing Results for #{@target_name}:\n"
        str << "  Iterations: #{@iterations}\n"
        str << "  Duration: #{@duration.total_milliseconds.round(2)}ms\n"
        str << "  Success Rate: #{(success_rate * 100).round(2)}%\n"
        str << "  Expected Error Rate: #{(error_rate * 100).round(2)}%\n"
        str << "  Crash Rate: #{(crash_rate * 100).round(2)}%\n"
        str << "  Timeouts: #{@timeouts}\n"
        if @crashes > 0
          str << "  ❌ CRASHES DETECTED: #{@crashes}\n"
        else
          str << "  ✅ No crashes detected\n"
        end
      end
    end
  end
end