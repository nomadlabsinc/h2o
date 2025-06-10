require "../spec_helper"

describe "Frame Processing Pipeline Performance" do
  it "measures baseline single frame processing performance" do
    # Create a buffer with mixed frame types
    frame_buffer = IO::Memory.new

    # Write different frame types
    100.times do |i|
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

    # Reset position for reading
    frame_buffer.rewind

    # Measure single frame processing time
    start_time = Time.monotonic
    frames_processed = 0

    100.times do
      frame = H2O::Frame.from_io(frame_buffer)
      frames_processed += 1
    end

    elapsed_time = Time.monotonic - start_time

    puts "\n=== BASELINE Frame Processing Performance ==="
    puts "Frames processed: #{frames_processed}"
    puts "Total time: #{elapsed_time.total_milliseconds.round(2)}ms"
    puts "Average time per frame: #{(elapsed_time.total_milliseconds / frames_processed).round(3)}ms"
    puts "Frames per second: #{(frames_processed / elapsed_time.total_seconds).round(0)}"
  end

  it "measures frame header parsing performance" do
    # Create pre-built frame headers
    headers = Array(Bytes).new

    1000.times do |i|
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

    # Measure parsing performance
    start_time = Time.monotonic
    parsed_count = 0

    headers.each do |header|
      # Parse frame header (simulate current parsing logic)
      length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
      frame_type = H2O::FrameType.new(header[3])
      flags = header[4]
      stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) |
                   (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32
      parsed_count += 1
    end

    elapsed_time = Time.monotonic - start_time

    puts "\n=== Frame Header Parsing Performance ==="
    puts "Headers parsed: #{parsed_count}"
    puts "Total time: #{elapsed_time.total_microseconds.round(2)}μs"
    puts "Average time per header: #{(elapsed_time.total_nanoseconds / parsed_count).round(0)}ns"
    puts "Headers per second: #{(parsed_count / elapsed_time.total_seconds).round(0)}"
  end

  it "measures buffer allocation overhead" do
    sizes = [9, 100, 1000, 10000, 16384]

    puts "\n=== Buffer Allocation Performance ==="

    sizes.each do |size|
      # Measure allocation time
      start_time = Time.monotonic
      allocations = 0

      10000.times do
        buffer = H2O::BufferPool.get_frame_buffer(size)
        H2O::BufferPool.return_frame_buffer(buffer)
        allocations += 1
      end

      elapsed_time = Time.monotonic - start_time

      puts "Size #{size} bytes:"
      puts "  Allocations: #{allocations}"
      puts "  Total time: #{elapsed_time.total_milliseconds.round(2)}ms"
      puts "  Average time: #{(elapsed_time.total_microseconds / allocations).round(2)}μs"
    end
  end
end
