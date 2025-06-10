require "../spec_helper"

describe "Frame Processing Pipeline Optimization - Performance Comparison" do
  it "compares single vs batch frame processing performance" do
    # Create a buffer with mixed frame types
    frame_buffer = IO::Memory.new
    frames_to_process = 1000

    # Write different frame types
    frames_to_process.times do |i|
      case i % 5
      when 0
        # DATA frame
        data = "Test data #{i}" * 10
        frame = H2O::DataFrame.new(1_u32, data.to_slice, 0_u8)
      when 1
        # HEADERS frame
        headers = H2O::Headers.new
        headers[":method"] = "GET"
        headers[":path"] = "/test#{i}"
        headers[":scheme"] = "https"
        headers[":authority"] = "example.com"
        encoder = H2O::HPACK::Encoder.new
        encoded = encoder.encode(headers)
        frame = H2O::HeadersFrame.new(1_u32, encoded, H2O::HeadersFrame::FLAG_END_HEADERS)
      when 2
        # SETTINGS frame
        settings = H2O::SettingsHash{H2O::SettingIdentifier::InitialWindowSize => 65536_u32}
        frame = H2O::SettingsFrame.new(settings)
      when 3
        # PING frame
        frame = H2O::PingFrame.new(Bytes.new(8, 0_u8))
      else
        # WINDOW_UPDATE frame
        frame = H2O::WindowUpdateFrame.new(0_u32, 65536_u32)
      end

      frame_buffer.write(frame.to_bytes)
    end

    puts "\n=== Frame Processing Performance Comparison ==="
    puts "Total frames to process: #{frames_to_process}"

    # Test 1: Single frame processing (baseline)
    frame_buffer.rewind
    start_time = Time.monotonic
    frames_processed = 0

    frames_to_process.times do
      frame = H2O::Frame.from_io(frame_buffer)
      frames_processed += 1
    end

    single_frame_time = Time.monotonic - start_time
    puts "\nSingle Frame Processing:"
    puts "  Total time: #{single_frame_time.total_milliseconds.round(2)}ms"
    puts "  Average time per frame: #{(single_frame_time.total_microseconds / frames_processed).round(2)}μs"
    puts "  Frames per second: #{(frames_processed / single_frame_time.total_seconds).round(0)}"

    # Test 2: Batch frame processing (optimized)
    frame_buffer.rewind
    batch_processor = H2O::FrameBatchProcessor.new
    start_time = Time.monotonic
    total_frames_batched = 0

    while total_frames_batched < frames_to_process
      frames = batch_processor.read_batch(frame_buffer)
      break if frames.empty?
      total_frames_batched += frames.size
    end

    batch_frame_time = Time.monotonic - start_time
    puts "\nBatch Frame Processing:"
    puts "  Total time: #{batch_frame_time.total_milliseconds.round(2)}ms"
    puts "  Average time per frame: #{(batch_frame_time.total_microseconds / total_frames_batched).round(2)}μs"
    puts "  Frames per second: #{(total_frames_batched / batch_frame_time.total_seconds).round(0)}"

    # Calculate improvement
    improvement = ((single_frame_time - batch_frame_time) / single_frame_time * 100).round(1)
    speedup = (single_frame_time.total_milliseconds / batch_frame_time.total_milliseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end

  it "measures optimized frame header parsing with lookup table" do
    # Create pre-built frame headers
    headers = Array(Bytes).new

    10000.times do |i|
      header = Bytes.new(9)
      # Length (3 bytes)
      length = 100_u32
      header[0] = ((length >> 16) & 0xff).to_u8
      header[1] = ((length >> 8) & 0xff).to_u8
      header[2] = (length & 0xff).to_u8
      # Type
      header[3] = (i % 10).to_u8 # Various frame types
      # Flags
      header[4] = 0_u8
      # Stream ID
      stream_id = (i % 100).to_u32 + 1
      header[5] = ((stream_id >> 24) & 0xff).to_u8
      header[6] = ((stream_id >> 16) & 0xff).to_u8
      header[7] = ((stream_id >> 8) & 0xff).to_u8
      header[8] = (stream_id & 0xff).to_u8

      headers << header
    end

    puts "\n=== Frame Header Parsing Performance Comparison ==="

    # Test 1: Traditional parsing with case statement
    start_time = Time.monotonic
    parsed_count = 0

    headers.each do |header|
      # Parse frame header (current approach)
      length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
      frame_type = H2O::FrameType.new(header[3])
      flags = header[4]
      stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) |
                   (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32
      parsed_count += 1
    end

    traditional_time = Time.monotonic - start_time

    # Test 2: Optimized parsing with lookup table
    start_time = Time.monotonic
    parsed_optimized = 0

    # Frame type lookup table
    frame_type_table = StaticArray[
      H2O::FrameType::Data,
      H2O::FrameType::Headers,
      H2O::FrameType::Priority,
      H2O::FrameType::RstStream,
      H2O::FrameType::Settings,
      H2O::FrameType::PushPromise,
      H2O::FrameType::Ping,
      H2O::FrameType::Goaway,
      H2O::FrameType::WindowUpdate,
      H2O::FrameType::Continuation,
    ]

    headers.each do |header|
      # Optimized parsing with unsafe_fetch
      length = (header.unsafe_fetch(0).to_u32 << 16) |
               (header.unsafe_fetch(1).to_u32 << 8) |
               header.unsafe_fetch(2).to_u32

      type_value = header.unsafe_fetch(3)
      frame_type = type_value < frame_type_table.size ? frame_type_table.unsafe_fetch(type_value) : H2O::FrameType.new(type_value)

      flags = header.unsafe_fetch(4)

      stream_id = (header.unsafe_fetch(5).to_u32 << 24) |
                  (header.unsafe_fetch(6).to_u32 << 16) |
                  (header.unsafe_fetch(7).to_u32 << 8) |
                  header.unsafe_fetch(8).to_u32
      stream_id &= 0x7fffffff_u32

      parsed_optimized += 1
    end

    optimized_time = Time.monotonic - start_time

    puts "Traditional parsing:"
    puts "  Headers parsed: #{parsed_count}"
    puts "  Total time: #{traditional_time.total_microseconds.round(2)}μs"
    puts "  Average time per header: #{(traditional_time.total_nanoseconds / parsed_count).round(0)}ns"

    puts "\nOptimized parsing:"
    puts "  Headers parsed: #{parsed_optimized}"
    puts "  Total time: #{optimized_time.total_microseconds.round(2)}μs"
    puts "  Average time per header: #{(optimized_time.total_nanoseconds / parsed_optimized).round(0)}ns"

    improvement = ((traditional_time - optimized_time) / traditional_time * 100).round(1)
    speedup = (traditional_time.total_microseconds / optimized_time.total_microseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end

  it "measures frame type-specific buffer allocation performance" do
    puts "\n=== Frame Type-Specific Buffer Allocation Performance ==="

    frame_types = [
      {type: H2O::FrameType::Data, typical_size: 16384, count: 1000},
      {type: H2O::FrameType::Headers, typical_size: 4096, count: 1000},
      {type: H2O::FrameType::Settings, typical_size: 36, count: 5000},
      {type: H2O::FrameType::Ping, typical_size: 8, count: 5000},
    ]

    # Test 1: Generic buffer allocation (one size fits all)
    generic_time = Time.monotonic
    generic_allocations = 0

    frame_types.each do |frame_info|
      frame_info[:count].times do
        # Always allocate max size buffer
        buffer = H2O::BufferPool.get_frame_buffer(16384)
        H2O::BufferPool.return_frame_buffer(buffer)
        generic_allocations += 1
      end
    end

    generic_time = Time.monotonic - generic_time

    # Test 2: Type-specific buffer allocation
    specific_time = Time.monotonic
    specific_allocations = 0

    frame_types.each do |frame_info|
      frame_info[:count].times do
        # Allocate size based on frame type
        buffer = H2O::BufferPool.get_frame_buffer(frame_info[:typical_size])
        H2O::BufferPool.return_frame_buffer(buffer)
        specific_allocations += 1
      end
    end

    specific_time = Time.monotonic - specific_time

    puts "Generic allocation (always 16KB):"
    puts "  Total allocations: #{generic_allocations}"
    puts "  Total time: #{generic_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(generic_time.total_microseconds / generic_allocations).round(2)}μs"

    puts "\nType-specific allocation:"
    puts "  Total allocations: #{specific_allocations}"
    puts "  Total time: #{specific_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(specific_time.total_microseconds / specific_allocations).round(2)}μs"

    improvement = ((generic_time - specific_time) / generic_time * 100).round(1)
    speedup = (generic_time.total_milliseconds / specific_time.total_milliseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end
end
