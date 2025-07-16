require "../spec_helper"
require "./framework/fuzzer"
require "./framework/native_fuzzer"
require "./targets/protocol_targets"

describe "Composable Fuzzing Framework" do
  describe "framework architecture" do
    it "supports pluggable fuzzing backends" do
      # Create different fuzzing targets
      frame_target = H2O::Fuzzing::FrameParsingTarget.new
      hpack_target = H2O::Fuzzing::HpackDecodingTarget.new

      # Use native Crystal fuzzer
      fuzzer = Crystal::Fuzzing::NativeFuzzer.new(seed: 12345)

      # Configure fuzzer
      config = Crystal::Fuzzing::FuzzConfig.new(
        seed: 12345_u32,
        max_input_size: 256,
        mutation_strategy: Crystal::Fuzzing::MutationStrategy::Hybrid,
        timeout_ms: 500
      )
      fuzzer.configure(config)

      # Run fuzzing on different targets
      frame_result = fuzzer.fuzz(frame_target, 50)
      hpack_result = fuzzer.fuzz(hpack_target, 50)

      # Verify results
      frame_result.target_name.should eq("Frame Parsing")
      frame_result.iterations.should eq(50)
      frame_result.crashes.should eq(0)

      hpack_result.target_name.should eq("HPACK Decoding")
      hpack_result.iterations.should eq(50)
      hpack_result.crashes.should eq(0)

      # Both should have some expected errors from malformed input
      (frame_result.expected_errors + frame_result.successes).should eq(50)
      (hpack_result.expected_errors + hpack_result.successes).should eq(50)
    end

    it "provides detailed fuzzing statistics" do
      target = H2O::Fuzzing::FrameParsingTarget.new
      fuzzer = Crystal::Fuzzing::NativeFuzzer.new(seed: 99999)

      result = fuzzer.fuzz(target, 25)

      # Verify comprehensive statistics
      result.iterations.should eq(25)
      result.duration.should be > Time::Span.zero
      result.crash_rate.should eq(0.0)                         # No crashes expected
      (result.success_rate + result.error_rate).should eq(1.0) # All iterations accounted for

      # Summary should be informative
      summary = result.summary
      summary.should contain("Fuzzing Results for Frame Parsing")
      summary.should contain("Iterations: 25")
      summary.should contain("No crashes detected")
    end

    it "handles different mutation strategies" do
      target = H2O::Fuzzing::HpackDecodingTarget.new

      # Test different strategies
      strategies = [
        Crystal::Fuzzing::MutationStrategy::Random,
        Crystal::Fuzzing::MutationStrategy::Mutational,
        Crystal::Fuzzing::MutationStrategy::Hybrid,
      ]

      strategies.each do |strategy|
        fuzzer = Crystal::Fuzzing::NativeFuzzer.new(seed: 55555)
        config = Crystal::Fuzzing::FuzzConfig.new(mutation_strategy: strategy)
        fuzzer.configure(config)

        result = fuzzer.fuzz(target, 10)

        result.iterations.should eq(10)
        result.crashes.should eq(0)
      end
    end
  end

  describe "Protocol Engine fuzzing targets" do
    it "frame parsing target handles malformed frames safely" do
      target = H2O::Fuzzing::FrameParsingTarget.new

      # Test with specific malformed inputs
      malformed_inputs = [
        Bytes[0xFF, 0xFF, 0xFF, 0x99, 0x99],                         # Invalid frame header
        Bytes[0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01], # Incomplete DATA frame
        Bytes.new(1000, 0xFF_u8),                                    # Large random data
        Bytes.empty,                                                 # Empty input
      ]

      malformed_inputs.each do |input|
        outcome = target.execute(input)
        outcome.should_not eq(Crystal::Fuzzing::FuzzOutcome::Crash)
      end
    end

    it "HPACK target provides appropriate seed inputs" do
      target = H2O::Fuzzing::HpackDecodingTarget.new
      seeds = target.seed_inputs

      seeds.should_not be_empty

      # Test that seed inputs are handled correctly
      seeds.each do |seed|
        outcome = target.execute(seed)
        # Seeds should either succeed or have expected errors
        outcome.should_not eq(Crystal::Fuzzing::FuzzOutcome::Crash)
      end
    end

    it "stream state machine target maintains engine stability" do
      target = H2O::Fuzzing::StreamStateMachineTarget.new

      # Test multiple executions to ensure clean state management
      10.times do |i|
        random_input = Bytes.new(20) { |j| (j + i * 3).to_u8 }
        outcome = target.execute(random_input)
        outcome.should_not eq(Crystal::Fuzzing::FuzzOutcome::Crash)
      end
    end

    it "flow control target handles edge cases" do
      target = H2O::Fuzzing::FlowControlTarget.new
      seeds = target.seed_inputs

      # Flow control seeds should trigger expected errors, not crashes
      seeds.each do |seed|
        outcome = target.execute(seed)
        # Some seeds are designed to trigger flow control errors
        [Crystal::Fuzzing::FuzzOutcome::Success, Crystal::Fuzzing::FuzzOutcome::ExpectedError].should contain(outcome)
      end
    end
  end

  describe "comprehensive protocol fuzzing" do
    it "runs systematic fuzzing across all protocol components" do
      targets = [
        H2O::Fuzzing::FrameParsingTarget.new,
        H2O::Fuzzing::HpackDecodingTarget.new,
        H2O::Fuzzing::StreamStateMachineTarget.new,
        H2O::Fuzzing::FlowControlTarget.new,
      ]

      fuzzer = Crystal::Fuzzing::NativeFuzzer.new(seed: 777777)
      config = Crystal::Fuzzing::FuzzConfig.new(
        max_input_size: 128,
        mutation_strategy: Crystal::Fuzzing::MutationStrategy::Hybrid,
        timeout_ms: 200
      )
      fuzzer.configure(config)

      total_iterations = 0
      total_crashes = 0

      targets.each do |target|
        result = fuzzer.fuzz(target, 20)

        result.crashes.should eq(0)
        result.iterations.should eq(20)

        total_iterations += result.iterations
        total_crashes += result.crashes

        puts "✅ #{target.name}: #{result.iterations} iterations, 0 crashes"
      end

      puts "\n🎯 Total Fuzzing Summary:"
      puts "   Total iterations: #{total_iterations}"
      puts "   Total crashes: #{total_crashes}"
      puts "   All protocol components handled fuzzing safely"

      total_crashes.should eq(0)
      total_iterations.should eq(80) # 4 targets × 20 iterations
    end
  end
end
