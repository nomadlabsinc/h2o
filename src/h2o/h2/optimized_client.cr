require "./client"
require "../io_optimizer"
require "../protocol_optimizer"

module H2O
  module H2
    # Optimized HTTP/2 client with I/O and protocol-level improvements
    class OptimizedClient < Client
      property batched_writer : IOOptimizer::BatchedWriter
      property frame_coalescer : ProtocolOptimizer::FrameCoalescer
      property io_stats : IOOptimizer::IOStats
      property priority_optimizer : ProtocolOptimizer::PriorityOptimizer
      property state_optimizer : ProtocolOptimizer::StateOptimizer
      property window_optimizer : ProtocolOptimizer::WindowUpdateOptimizer
      property zero_copy_reader : IOOptimizer::ZeroCopyReader
      property zero_copy_writer : IOOptimizer::ZeroCopyWriter

      def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds)
        super(hostname, port, connect_timeout)

        # Optimize socket for HTTP/2 if possible
        IOOptimizer::SocketOptimizer.optimize(@socket)

        # Initialize I/O optimizers
        @zero_copy_reader = IOOptimizer::ZeroCopyReader.new(@socket)
        @zero_copy_writer = IOOptimizer::ZeroCopyWriter.new(@socket)
        @batched_writer = IOOptimizer::BatchedWriter.new(@socket)
        @io_stats = IOOptimizer::IOStats.new

        # Initialize protocol optimizers
        @frame_coalescer = ProtocolOptimizer::FrameCoalescer.new
        @window_optimizer = ProtocolOptimizer::WindowUpdateOptimizer.new
        @priority_optimizer = ProtocolOptimizer::PriorityOptimizer.new
        @state_optimizer = ProtocolOptimizer::StateOptimizer.new

        # Apply optimized settings
        apply_optimized_settings
      end

      private def apply_optimized_settings : Nil
        # Use balanced settings by default
        settings = ProtocolOptimizer::SettingsOptimizer.balanced_settings
        settings_frame = SettingsFrame.new

        settings.each do |identifier, value|
          settings_frame[identifier] = value
        end

        send_frame(settings_frame)
      end

      # Override reader loop for zero-copy I/O
      private def reader_loop : Nil
        frame_header_buffer = Bytes.new(9)

        loop do
          break if @closed || @closing

          begin
            # Zero-copy read of frame header
            @zero_copy_reader.read_fully_into(frame_header_buffer)

            # Parse frame header efficiently
            length = (frame_header_buffer[0].to_u32 << 16) |
                     (frame_header_buffer[1].to_u32 << 8) |
                     frame_header_buffer[2].to_u32

            type = frame_header_buffer[3]
            flags = frame_header_buffer[4]
            stream_id = ((frame_header_buffer[5].to_u32 << 24) |
                         (frame_header_buffer[6].to_u32 << 16) |
                         (frame_header_buffer[7].to_u32 << 8) |
                         frame_header_buffer[8].to_u32) & 0x7FFFFFFF

            # Zero-copy read of payload
            payload = if length > 0
                        payload_buffer = Bytes.new(length)
                        @zero_copy_reader.read_fully_into(payload_buffer)
                        payload_buffer
                      else
                        Bytes.empty
                      end

            frame = parse_frame(type, flags, stream_id, payload)
            handle_incoming_frame(frame)
          rescue ex : IO::Error
            break
          rescue ex
            handle_error(ex)
            break
          end
        end
      ensure
        close_connection
      end

      # Override writer loop for batched I/O
      private def writer_loop : Nil
        batch_timeout = 1.milliseconds
        last_flush = Time.monotonic

        loop do
          break if @closed

          begin
            # Try to get frame with timeout for batching
            frame = receive_with_timeout(batch_timeout)

            if frame
              # Check for coalescing opportunity
              if @frame_coalescer.add(frame)
                # Frame added to coalescer
                if coalesced = @frame_coalescer.get_coalesced
                  # Write coalesced frames
                  write_coalesced_frames(coalesced)
                end
              else
                # Write frame immediately
                write_optimized_frame(frame)
              end
            end

            # Periodic flush
            now = Time.monotonic
            if now - last_flush > batch_timeout
              @batched_writer.flush
              last_flush = now
            end

            # Process any pending window updates
            process_window_updates
          rescue Channel::ClosedError
            break
          rescue ex
            handle_error(ex)
            break
          end
        end
      ensure
        @batched_writer.flush
      end

      private def write_optimized_frame(frame : Frame) : Nil
        # Get frame bytes
        frame_bytes = frame.to_bytes

        # Add to batch for small frames
        if frame_bytes.size < IOOptimizer::SMALL_BUFFER_SIZE
          @batched_writer.add(frame_bytes)
        else
          # Large frames bypass batching
          @batched_writer.flush # Flush any pending small frames
          @zero_copy_writer.write_from(frame_bytes)
        end
      end

      private def write_coalesced_frames(frames : Array(Frame)) : Nil
        # Combine frame bytes for single write
        buffers = frames.map(&.to_bytes)
        @zero_copy_writer.write_buffers(buffers)
      end

      private def process_window_updates : Nil
        updates = @window_optimizer.get_updates
        return if updates.empty?

        updates.each do |update|
          frame = WindowUpdateFrame.new(update.stream_id, update.increment)
          @batched_writer.add(frame.to_bytes)
        end
      end

      # Override to track consumed bytes for window management
      def handle_data_frame(frame : DataFrame) : Nil
        super(frame)
        @window_optimizer.consume(frame.stream_id, frame.length.to_i32)
      end

      # Override to apply priority optimization
      def send_request(request : Request, headers : Headers) : Response?
        # Optimize priority based on content type hint
        if accept = headers["accept"]?
          stream = @stream_pool.create_stream
          @priority_optimizer.optimize_by_content_type(stream.id, accept)
        end

        super(request, headers)
      end

      # Get I/O statistics
      def io_statistics : IOOptimizer::IOStats
        stats = IOOptimizer::IOStats.new
        stats.bytes_read = @zero_copy_reader.stats.bytes_read + @io_stats.bytes_read
        stats.bytes_written = @zero_copy_writer.stats.bytes_written + @batched_writer.stats.bytes_written
        stats.read_operations = @zero_copy_reader.stats.read_operations + @io_stats.read_operations
        stats.write_operations = @zero_copy_writer.stats.write_operations + @batched_writer.stats.write_operations
        stats.batches_flushed = @batched_writer.stats.batches_flushed
        stats.total_read_time = @zero_copy_reader.stats.total_read_time + @io_stats.total_read_time
        stats.total_write_time = @zero_copy_writer.stats.total_write_time + @batched_writer.stats.total_write_time
        stats
      end

      # Cache HTTP/2 support for host
      def cache_http2_support(supported : Bool) : Nil
        if host = URI.parse("https://#{@socket.hostname}").host
          @state_optimizer.cache_http2_support(host, supported)
        end
      end

      # Check cached HTTP/2 support
      def cached_http2_support? : Bool?
        if host = URI.parse("https://#{@socket.hostname}").host
          @state_optimizer.http2_supported?(host)
        end
      end

      private def parse_frame(type : UInt8, flags : UInt8, stream_id : UInt32, payload : Bytes) : Frame
        frame_type = FrameType.from_value?(type) || raise FrameError.new("Unknown frame type: #{type}")

        case frame_type
        when FrameType::Data
          DataFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::Headers
          HeadersFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::Settings
          SettingsFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::WindowUpdate
          WindowUpdateFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::Ping
          PingFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::GoAway
          GoAwayFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::RstStream
          RstStreamFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::Priority
          PriorityFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::PushPromise
          PushPromiseFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        when FrameType::Continuation
          ContinuationFrame.from_payload(payload.size.to_u32, flags, stream_id, payload)
        else
          raise FrameError.new("Unhandled frame type: #{frame_type}")
        end
      end

      # Helper for timeout receives
      private def receive_with_timeout(timeout_span : Time::Span) : Frame?
        start_time = Time.monotonic
        loop do
          select
          when frame = @outgoing_frames.receive?
            return frame
          else
            if Time.monotonic - start_time > timeout_span
              return nil
            end
            Fiber.yield
          end
        end
      end
    end
  end
end
