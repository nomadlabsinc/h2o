require "./frame"

module H2O
  # FrameWriter encapsulates HTTP/2 frame writing to IO streams
  # This class strictly handles frame serialization and I/O, separating
  # frame writing concerns from connection management (Layer 2 of refactor)
  class FrameWriter
    FRAME_HEADER_SIZE = 9_u8

    def initialize(@io : IO)
    end

    # Write a single frame to the IO stream
    # Handles frame serialization and efficient I/O
    def write_frame(frame : Frame) : Nil
      # Serialize frame to bytes
      frame_bytes = frame.to_bytes

      # Write frame data to IO
      @io.write(frame_bytes)
      @io.flush
    end

    # Write multiple frames efficiently
    def write_frames(frames : Array(Frame)) : Nil
      frames.each do |frame|
        write_frame(frame)
      end
    end

    # Write frame with buffering for efficiency
    # Uses buffer pool to reduce memory allocations
    def write_frame_buffered(frame : Frame) : Nil
      # Calculate total frame size
      header_size = FRAME_HEADER_SIZE.to_i32
      payload_bytes = frame.payload_to_bytes
      total_size = header_size + payload_bytes.size

      # Use buffer pool for efficient writing
      H2O::BufferPool.with_buffer(total_size) do |buffer|
        # Write frame header
        write_header_to_buffer(buffer, frame)

        # Write payload if present
        if payload_bytes.size > 0
          buffer[header_size, payload_bytes.size].copy_from(payload_bytes)
        end

        # Write buffered data to IO
        @io.write(buffer[0, total_size])
      end

      @io.flush
    end

    # Write multiple frames with efficient batching
    def write_frames_batched(frames : Array(Frame)) : Nil
      # Calculate total buffer size needed
      total_size = frames.sum do |frame|
        FRAME_HEADER_SIZE.to_i32 + frame.payload_to_bytes.size
      end

      # Use buffer pool for batch writing
      H2O::BufferPool.with_buffer(total_size) do |buffer|
        offset = 0

        frames.each do |frame|
          # Write frame header
          write_header_to_buffer(buffer[offset, FRAME_HEADER_SIZE.to_i32], frame)
          offset += FRAME_HEADER_SIZE.to_i32

          # Write payload if present
          payload_bytes = frame.payload_to_bytes
          if payload_bytes.size > 0
            buffer[offset, payload_bytes.size].copy_from(payload_bytes)
            offset += payload_bytes.size
          end
        end

        # Write all frames at once
        @io.write(buffer[0, total_size])
      end

      @io.flush
    end

    # Check if IO is available for writing
    def available? : Bool
      !@io.closed?
    end

    private def write_header_to_buffer(buffer : Bytes, frame : Frame) : Nil
      # Write frame length (24 bits)
      buffer[0] = ((frame.length >> 16) & 0xff).to_u8
      buffer[1] = ((frame.length >> 8) & 0xff).to_u8
      buffer[2] = (frame.length & 0xff).to_u8

      # Write frame type
      buffer[3] = frame.frame_type.value

      # Write flags
      buffer[4] = frame.flags

      # Write stream ID (31 bits, with reserved bit clear)
      buffer[5] = ((frame.stream_id >> 24) & 0xff).to_u8
      buffer[6] = ((frame.stream_id >> 16) & 0xff).to_u8
      buffer[7] = ((frame.stream_id >> 8) & 0xff).to_u8
      buffer[8] = (frame.stream_id & 0xff).to_u8
    end
  end
end
