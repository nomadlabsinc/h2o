require "./fuzzer"

module Crystal::Fuzzing
  # Native Crystal fuzzer implementation
  # Uses Crystal's Random and built-in capabilities for mutation
  class NativeFuzzer < Fuzzer
    property random : Random
    property config : FuzzConfig

    def initialize(seed : UInt32? = nil)
      @config = FuzzConfig.new(seed: seed)
      @random = seed ? Random.new(seed) : Random.new
    end

    def configure(@config : FuzzConfig) : Nil
      if seed = @config.seed
        @random = Random.new(seed)
      end
    end

    def fuzz(target : FuzzTarget, iterations : Int32) : FuzzResult
      result = FuzzResult.new(target.name)
      start_time = Time.monotonic

      iterations.times do |i|
        result.iterations += 1

        # Generate input based on strategy
        input = generate_input(target)

        # Execute with timeout
        outcome = execute_with_timeout(target, input)

        case outcome
        when FuzzOutcome::Success
          result.successes += 1
        when FuzzOutcome::ExpectedError
          result.expected_errors += 1
        when FuzzOutcome::Crash
          result.crashes += 1
          result.crash_inputs << input
        end
      end

      result.duration = Time.monotonic - start_time
      result
    end

    private def generate_input(target : FuzzTarget) : Bytes
      case @config.mutation_strategy
      when .random?
        generate_random_input
      when .mutational?
        generate_mutated_input(target)
      when .generative?
        generate_structured_input(target)
      when .hybrid?
        # Randomly choose strategy for each input
        case @random.rand(3)
        when 0
          generate_random_input
        when 1
          generate_mutated_input(target)
        else
          generate_structured_input(target)
        end
      else
        generate_random_input
      end
    end

    private def generate_random_input : Bytes
      size = 1 + @random.rand(@config.max_input_size)
      bytes = Bytes.new(size)
      size.times do |i|
        bytes[i] = @random.rand(256).to_u8
      end
      bytes
    end

    private def generate_mutated_input(target : FuzzTarget) : Bytes
      seeds = target.seed_inputs
      if seeds.empty?
        return generate_random_input
      end

      # Pick random seed and mutate it
      seed = seeds.sample(@random)
      mutate_bytes(seed)
    end

    private def generate_structured_input(target : FuzzTarget) : Bytes
      # For now, same as random - can be overridden for specific domains
      generate_random_input
    end

    private def mutate_bytes(original : Bytes) : Bytes
      # Create a copy to mutate
      mutated = Bytes.new(original.size + @random.rand(10)) # Slightly vary size
      original.copy_to(mutated)

      # Apply random mutations
      max_mutations = [mutated.size // 4, 10].min
      max_mutations = 1 if max_mutations == 0 # Ensure at least 1
      mutation_count = 1 + @random.rand(max_mutations)
      mutation_count.times do
        case @random.rand(6)
        when 0
          # Bit flip
          if mutated.size > 0
            byte_idx = @random.rand(mutated.size)
            bit_idx = @random.rand(8)
            mutated[byte_idx] ^= (1_u8 << bit_idx)
          end
        when 1
          # Byte replacement
          if mutated.size > 0
            mutated[@random.rand(mutated.size)] = @random.rand(256).to_u8
          end
        when 2
          # Insert random byte
          if mutated.size < @config.max_input_size
            insert_pos = @random.rand(mutated.size + 1)
            new_mutated = Bytes.new(mutated.size + 1)
            new_mutated[0, insert_pos].copy_from(mutated[0, insert_pos])
            new_mutated[insert_pos] = @random.rand(256).to_u8
            new_mutated[insert_pos + 1, mutated.size - insert_pos].copy_from(mutated[insert_pos, mutated.size - insert_pos])
            mutated = new_mutated
          end
        when 3
          # Delete byte
          if mutated.size > 1
            delete_pos = @random.rand(mutated.size)
            new_mutated = Bytes.new(mutated.size - 1)
            if delete_pos > 0
              new_mutated[0, delete_pos].copy_from(mutated[0, delete_pos])
            end
            if delete_pos < mutated.size - 1
              new_mutated[delete_pos, mutated.size - delete_pos - 1].copy_from(mutated[delete_pos + 1, mutated.size - delete_pos - 1])
            end
            mutated = new_mutated
          end
        when 4
          # Duplicate sequence
          if mutated.size > 4 && mutated.size < @config.max_input_size - 4
            seq_start = @random.rand(mutated.size - 2)
            seq_len = 1 + @random.rand([4, mutated.size - seq_start].min)
            dup_pos = @random.rand(mutated.size + 1)

            new_mutated = Bytes.new(mutated.size + seq_len)
            new_mutated[0, dup_pos].copy_from(mutated[0, dup_pos])
            new_mutated[dup_pos, seq_len].copy_from(mutated[seq_start, seq_len])
            new_mutated[dup_pos + seq_len, mutated.size - dup_pos].copy_from(mutated[dup_pos, mutated.size - dup_pos])
            mutated = new_mutated
          end
        when 5
          # Magic number insertion
          magic_numbers = [0x00_u8, 0xFF_u8, 0x7F_u8, 0x80_u8]
          if mutated.size > 0
            mutated[@random.rand(mutated.size)] = magic_numbers.sample(@random)
          end
        end
      end

      mutated
    end

    private def execute_with_timeout(target : FuzzTarget, input : Bytes) : FuzzOutcome
      # Simple timeout implementation using spawn and channels
      result_channel = Channel(FuzzOutcome).new

      spawn do
        begin
          outcome = target.execute(input)
          result_channel.send(outcome)
        rescue
          result_channel.send(FuzzOutcome::Crash)
        end
      end

      select
      when outcome = result_channel.receive
        outcome
      when timeout(@config.timeout_ms.milliseconds)
        FuzzOutcome::Crash # Treat timeout as crash
      end
    end
  end
end
