require "../spec_helper"
require "../../src/h2o"

describe "I/O Optimization Baseline Performance" do
  it "measures baseline I/O performance without optimization" do
    puts "\n=== BASELINE I/O Performance ==="

    # Create test data of various sizes
    small_data = Bytes.new(1024) { |i| (i % 256).to_u8 }   # 1KB
    medium_data = Bytes.new(16384) { |i| (i % 256).to_u8 } # 16KB
    large_data = Bytes.new(65536) { |i| (i % 256).to_u8 }  # 64KB

    iterations = 10_000

    # Test 1: Individual writes (no batching)
    io = IO::Memory.new
    start_time = Time.monotonic

    iterations.times do |i|
      # Simulate writing individual frames
      data = case i % 3
             when 0 then small_data
             when 1 then medium_data
             else        large_data
             end

      io.write(data)
    end

    individual_write_time = Time.monotonic - start_time
    total_bytes = io.size

    puts "Individual writes (no batching):"
    puts "  Iterations: #{iterations}"
    puts "  Total bytes: #{(total_bytes / 1024.0 / 1024.0).round(2)}MB"
    puts "  Total time: #{individual_write_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{(total_bytes / individual_write_time.total_seconds / 1024.0 / 1024.0).round(2)}MB/s"
    puts "  Average time per write: #{(individual_write_time.total_microseconds / iterations).round(2)}μs"
  end

  it "measures baseline frame parsing performance" do
    puts "\n=== BASELINE Frame Parsing Performance ==="

    iterations = 100_000

    # Create sample frame header
    frame_header = Bytes.new(9)
    frame_header[0] = 0x00 # Length high
    frame_header[1] = 0x00 # Length mid
    frame_header[2] = 0x0A # Length low (10 bytes)
    frame_header[3] = 0x00 # Type (DATA)
    frame_header[4] = 0x01 # Flags
    frame_header[5] = 0x00 # Stream ID
    frame_header[6] = 0x00
    frame_header[7] = 0x00
    frame_header[8] = 0x01

    # Test: Traditional frame header parsing
    start_time = Time.monotonic

    iterations.times do
      # Simulate traditional parsing with multiple reads
      io = IO::Memory.new(frame_header)

      # Read length (3 bytes)
      length_bytes = Bytes.new(3)
      io.read_fully(length_bytes)
      length = (length_bytes[0].to_u32 << 16) | (length_bytes[1].to_u32 << 8) | length_bytes[2].to_u32

      # Read type and flags
      type = io.read_byte.not_nil!
      flags = io.read_byte.not_nil!

      # Read stream ID (4 bytes)
      stream_id_bytes = Bytes.new(4)
      io.read_fully(stream_id_bytes)
      stream_id = ((stream_id_bytes[0].to_u32 << 24) |
                   (stream_id_bytes[1].to_u32 << 16) |
                   (stream_id_bytes[2].to_u32 << 8) |
                   stream_id_bytes[3].to_u32) & 0x7FFFFFFF
    end

    traditional_parse_time = Time.monotonic - start_time

    puts "Traditional frame header parsing:"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{traditional_parse_time.total_milliseconds.round(2)}ms"
    puts "  Average time per parse: #{(traditional_parse_time.total_nanoseconds / iterations).round(0)}ns"
    puts "  Parses per second: #{(iterations / traditional_parse_time.total_seconds).round(0)}"
  end

  it "measures baseline buffer allocation overhead" do
    puts "\n=== BASELINE Buffer Allocation Overhead ==="

    iterations = 50_000
    sizes = [1024, 4096, 16384, 65536] # 1KB, 4KB, 16KB, 64KB

    sizes.each do |size|
      start_time = Time.monotonic
      buffers = Array(Bytes).new

      iterations.times do
        # Allocate new buffer each time
        buffer = Bytes.new(size)
        buffers << buffer if buffers.size < 100 # Keep some to prevent immediate GC
      end

      allocation_time = Time.monotonic - start_time

      puts "\n#{size} byte buffers:"
      puts "  Iterations: #{iterations}"
      puts "  Total time: #{allocation_time.total_milliseconds.round(2)}ms"
      puts "  Average allocation time: #{(allocation_time.total_microseconds / iterations).round(2)}μs"
      puts "  Allocations per second: #{(iterations / allocation_time.total_seconds).round(0)}"
    end
  end

  it "measures baseline syscall overhead" do
    puts "\n=== BASELINE Syscall Overhead ==="

    # Create a pipe for real I/O testing
    reader, writer = IO.pipe

    iterations = 10_000
    data = Bytes.new(100) { |i| (i % 256).to_u8 }

    # Spawn reader fiber
    spawn do
      buffer = Bytes.new(100)
      iterations.times do
        reader.read_fully(buffer)
      end
    end

    # Measure write syscalls
    start_time = Time.monotonic

    iterations.times do
      writer.write(data)
      writer.flush # Force syscall
    end

    syscall_time = Time.monotonic - start_time

    puts "Individual syscalls (100 byte writes):"
    puts "  Iterations: #{iterations}"
    puts "  Total time: #{syscall_time.total_milliseconds.round(2)}ms"
    puts "  Average syscall time: #{(syscall_time.total_microseconds / iterations).round(2)}μs"
    puts "  Syscalls per second: #{(iterations / syscall_time.total_seconds).round(0)}"

    reader.close
    writer.close
  end
end
