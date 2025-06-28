module H2O
  # Optimized batch frame processor for improved performance
  class FrameBatchProcessor
    BATCH_SIZE = 10

    # Frame type lookup table for faster parsing
    FRAME_TYPE_TABLE = StaticArray[
      FrameType::Data,         # 0x0
      FrameType::Headers,      # 0x1
      FrameType::Priority,     # 0x2
      FrameType::RstStream,    # 0x3
      FrameType::Settings,     # 0x4
      FrameType::PushPromise,  # 0x5
      FrameType::Ping,         # 0x6
      FrameType::Goaway,       # 0x7
      FrameType::WindowUpdate, # 0x8
      FrameType::Continuation, # 0x9
    ]

    # Frame type specific buffer sizes
    FRAME_SIZE_HINTS = {
      FrameType::Data         => 16384, # Large data frames
      FrameType::Headers      => 4096,  # Medium header blocks
      FrameType::Priority     => 5,     # Fixed 5 bytes
      FrameType::RstStream    => 4,     # Fixed 4 bytes
      FrameType::Settings     => 36,    # 6 settings * 6 bytes each
      FrameType::PushPromise  => 4096,  # Similar to headers
      FrameType::Ping         => 8,     # Fixed 8 bytes
      FrameType::Goaway       => 8,     # Fixed 8 bytes minimum
      FrameType::WindowUpdate => 4,     # Fixed 4 bytes
      FrameType::Continuation => 4096,  # Similar to headers
    }

    property batch_buffer : Bytes
    property frames : Array(Frame)
    property read_buffer : IO::Memory

    def initialize
      @batch_buffer = Bytes.new(Frame::FRAME_HEADER_SIZE * BATCH_SIZE)
      @frames = Array(Frame).new(BATCH_SIZE)
      @read_buffer = IO::Memory.new(65536) # 64KB read buffer
    end

    # Read and process frames in batches
    def read_batch(io : IO, max_frame_size : UInt32 = Frame::MAX_FRAME_SIZE) : Array(Frame)
      @frames.clear

      # Read up to BATCH_SIZE frames
      BATCH_SIZE.times do
        begin
          # Check if we can read a frame header
          header = Bytes.new(Frame::FRAME_HEADER_SIZE)
          io.read_fully(header)

          # Parse the header
          length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
          type_value = header[3]
          frame_type = type_value < FRAME_TYPE_TABLE.size ? FRAME_TYPE_TABLE.unsafe_fetch(type_value) : FrameType.new(type_value)
          flags = header[4]
          stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) |
                       (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32

          # Validate frame size
          if length > max_frame_size
            raise FrameError.new("Frame size #{length} exceeds maximum allowed size #{max_frame_size}")
          end

          # Read payload if needed
          payload = if length > 0
                      payload_buf = BufferPool.get_frame_buffer(length.to_i32)[0, length]
                      io.read_fully(payload_buf)
                      payload_buf
                    else
                      Bytes.empty
                    end

          # Create and add frame
          frame = create_frame_optimized(frame_type, length, flags, stream_id, payload)
          @frames << frame
        rescue IO::EOFError
          # End of stream, return what we have
          break
        end
      end

      @frames
    end

    # Optimized frame header parsing with lookup table
    private def parse_frame_at_offset(io : IO, offset : Int32) : Frame
      header = @batch_buffer[offset, Frame::FRAME_HEADER_SIZE]

      # Fast bit manipulation for frame header parsing
      length = (header.unsafe_fetch(0).to_u32 << 16) |
               (header.unsafe_fetch(1).to_u32 << 8) |
               header.unsafe_fetch(2).to_u32

      # Use lookup table for frame type
      type_value = header.unsafe_fetch(3)
      frame_type = type_value < FRAME_TYPE_TABLE.size ? FRAME_TYPE_TABLE.unsafe_fetch(type_value) : FrameType.new(type_value)

      flags = header.unsafe_fetch(4)

      # Fast stream ID extraction
      stream_id = (header.unsafe_fetch(5).to_u32 << 24) |
                  (header.unsafe_fetch(6).to_u32 << 16) |
                  (header.unsafe_fetch(7).to_u32 << 8) |
                  header.unsafe_fetch(8).to_u32
      stream_id &= 0x7fffffff_u32

      # Get appropriately sized buffer for payload
      payload_size = get_buffer_size_hint(frame_type, length)
      payload = BufferPool.get_frame_buffer(payload_size.to_i32)[0, length]
      io.read_fully(payload) if length > 0

      # Create frame using optimized factory method
      create_frame_optimized(frame_type, length, flags, stream_id, payload)
    end

    # Get optimal buffer size for frame type
    private def get_buffer_size_hint(frame_type : FrameType, actual_length : UInt32) : UInt32
      hint = FRAME_SIZE_HINTS[frame_type]? || 1024
      Math.max(actual_length, hint.to_u32)
    end

    # Optimized frame creation avoiding multiple case statements
    private def create_frame_optimized(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : Frame
      case frame_type
      when .data?
        DataFrame.from_payload(length, flags, stream_id, payload)
      when .headers?
        HeadersFrame.from_payload(length, flags, stream_id, payload)
      when .settings?
        SettingsFrame.from_payload(length, flags, stream_id, payload)
      when .ping?
        PingFrame.from_payload(length, flags, stream_id, payload)
      when .window_update?
        WindowUpdateFrame.from_payload(length, flags, stream_id, payload)
      when .goaway?
        GoawayFrame.from_payload(length, flags, stream_id, payload)
      when .rst_stream?
        RstStreamFrame.from_payload(length, flags, stream_id, payload)
      when .priority?
        PriorityFrame.from_payload(length, flags, stream_id, payload)
      when .continuation?
        ContinuationFrame.from_payload(length, flags, stream_id, payload)
      when .push_promise?
        PushPromiseFrame.from_payload(length, flags, stream_id, payload)
      else
        raise FrameError.new("Unknown frame type: #{frame_type}")
      end
    end
  end
end
