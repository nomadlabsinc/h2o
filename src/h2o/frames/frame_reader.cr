require "./frame"
require "./frame_validation"

module H2O
  # FrameReader encapsulates HTTP/2 frame reading from IO streams
  # This class strictly handles frame parsing and validation, separating
  # frame I/O concerns from connection management (Layer 2 of refactor)
  class FrameReader
    FRAME_HEADER_SIZE = 9_u8

    def initialize(@io : IO, @max_frame_size : UInt32 = Frame::MAX_FRAME_SIZE)
    end

    # Read a single frame from the IO stream
    # Applies frame-level validation before returning
    def read_frame : Frame
      # Read frame header using buffer pool
      header = H2O::BufferPool.with_buffer(FRAME_HEADER_SIZE.to_i32) do |buffer|
        header_slice = buffer[0, FRAME_HEADER_SIZE.to_i32]
        @io.read_fully(header_slice)

        # Copy header data out of pooled buffer
        Bytes.new(FRAME_HEADER_SIZE.to_i32) do |i|
          header_slice[i]
        end
      end

      # Parse frame header
      length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
      frame_type = FrameType.new(header[3])
      flags = header[4]
      stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) |
                   (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32

      # STRICT VALIDATION: Fail fast on protocol violations
      # 1. Validate frame size BEFORE reading payload
      FrameValidation.validate_frame_size(length, @max_frame_size)

      # 2. Validate stream ID constraints per frame type
      FrameValidation.validate_stream_id_for_frame_type(frame_type, stream_id)

      # Read payload using buffer pool safely
      payload = if length > 0
                  H2O::BufferPool.with_buffer(length.to_i32) do |buffer|
                    # Read into the pooled buffer
                    read_slice = buffer[0, length.to_i32]
                    @io.read_fully(read_slice)

                    # Copy to right-sized Bytes that the frame will own
                    Bytes.new(length.to_i32) do |i|
                      read_slice[i]
                    end
                  end
                else
                  Bytes.empty
                end

      # Create frame from parsed data
      frame = create_frame(frame_type, length, flags, stream_id, payload)

      # 3. Apply comprehensive frame validation
      FrameValidation.validate_frame_comprehensive(frame)

      frame
    end

    # Read multiple frames until a condition is met
    def read_frames_until(& : Frame -> Bool) : Array(Frame)
      frames = Array(Frame).new

      loop do
        frame = read_frame
        frames << frame
        break if yield frame
      end

      frames
    end

    # Check if more data is available to read
    def available? : Bool
      !@io.closed?
    end

    private def create_frame(frame_type : FrameType, length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : Frame
      case frame_type
      when .data?
        DataFrame.from_payload(length, flags, stream_id, payload)
      when .headers?
        HeadersFrame.from_payload(length, flags, stream_id, payload)
      when .priority?
        PriorityFrame.from_payload(length, flags, stream_id, payload)
      when .rst_stream?
        RstStreamFrame.from_payload(length, flags, stream_id, payload)
      when .settings?
        SettingsFrame.from_payload(length, flags, stream_id, payload)
      when .push_promise?
        PushPromiseFrame.from_payload(length, flags, stream_id, payload)
      when .ping?
        PingFrame.from_payload(length, flags, stream_id, payload)
      when .goaway?
        GoawayFrame.from_payload(length, flags, stream_id, payload)
      when .window_update?
        WindowUpdateFrame.from_payload(length, flags, stream_id, payload)
      when .continuation?
        ContinuationFrame.from_payload(length, flags, stream_id, payload)
      else
        # RFC 7540 Section 4.1: Unknown frame types must be ignored
        UnknownFrame.new(length, frame_type, flags, stream_id, payload)
      end
    end
  end
end
