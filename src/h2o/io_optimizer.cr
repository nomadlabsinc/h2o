module H2O
  # I/O optimization utilities for high-performance network operations
  module IOOptimizer
    # Buffer sizes for different operation types
    SMALL_BUFFER_SIZE  =  4_096 # 4KB for control frames
    MEDIUM_BUFFER_SIZE = 16_384 # 16KB for typical data
    LARGE_BUFFER_SIZE  = 65_536 # 64KB for large transfers

    # Batch operation thresholds
    MIN_BATCH_SIZE =  3
    MAX_BATCH_SIZE = 10
    BATCH_TIMEOUT  = 1.milliseconds

    # Socket buffer optimization settings
    DEFAULT_RECV_BUFFER = 262_144 # 256KB
    DEFAULT_SEND_BUFFER = 262_144 # 256KB

    # Zero-copy I/O helper for reading directly into buffers
    struct ZeroCopyReader
      property io : IO
      property stats : IOStats

      def initialize(@io : IO)
        @stats = IOStats.new
      end

      # Read directly into a pre-allocated buffer without copying
      def read_into(buffer : Bytes) : Int32
        start_time = Time.monotonic
        bytes_read = @io.read(buffer)
        @stats.record_read(bytes_read, Time.monotonic - start_time)
        bytes_read
      end

      # Read exact amount into buffer or raise
      def read_fully_into(buffer : Bytes) : Nil
        start_time = Time.monotonic
        @io.read_fully(buffer)
        @stats.record_read(buffer.size, Time.monotonic - start_time)
      end

      # Peek at data without consuming it (if supported)
      def peek(size : Int32) : Bytes?
        if @io.responds_to?(:peek)
          @io.peek(size)
        else
          nil
        end
      end

      # Transfer file content efficiently
      def transfer_file(file_path : String, output_io : IO) : Int32
        start_time = Time.monotonic
        bytes_transferred = 0

        File.open(file_path, "r") do |file|
          buffer = Bytes.new(MEDIUM_BUFFER_SIZE)
          while (bytes_read = file.read(buffer)) > 0
            output_io.write(buffer[0, bytes_read])
            bytes_transferred += bytes_read
          end
        end

        @stats.record_read(bytes_transferred, Time.monotonic - start_time)
        bytes_transferred
      end
    end

    # Zero-copy I/O helper for writing from buffers
    struct ZeroCopyWriter
      property io : IO
      property stats : IOStats

      def initialize(@io : IO)
        @stats = IOStats.new
      end

      # Write directly from buffer without copying
      def write_from(buffer : Bytes) : Nil
        start_time = Time.monotonic
        @io.write(buffer)
        @stats.record_write(buffer.size, Time.monotonic - start_time)
      end

      # Write multiple buffers efficiently (vectored I/O simulation)
      def write_buffers(buffers : Array(Bytes)) : Nil
        start_time = Time.monotonic
        total_bytes = 0

        buffers.each do |buffer|
          @io.write(buffer)
          total_bytes += buffer.size
        end

        @stats.record_write(total_bytes, Time.monotonic - start_time)
      end

      # Serve file content efficiently
      def serve_file(file_path : String) : Int32
        start_time = Time.monotonic
        bytes_written = 0

        File.open(file_path, "r") do |file|
          buffer = Bytes.new(MEDIUM_BUFFER_SIZE)
          while (bytes_read = file.read(buffer)) > 0
            @io.write(buffer[0, bytes_read])
            bytes_written += bytes_read
          end
        end

        @stats.record_write(bytes_written, Time.monotonic - start_time)
        bytes_written
      end

      # Vectored write (writev simulation)
      def writev(buffers : Array(Bytes)) : Int32
        start_time = Time.monotonic
        total_bytes = 0

        buffers.each do |buffer|
          @io.write(buffer)
          total_bytes += buffer.size
        end

        @stats.record_write(total_bytes, Time.monotonic - start_time)
        total_bytes
      end
    end

    # I/O operation batching for reduced syscalls
    class BatchedWriter
      property buffers : Array(Bytes)
      property io : IO
      property max_batch_size : Int32
      property mutex : Mutex
      property stats : IOStats
      property timeout : Time::Span
      property total_size : Int32

      def initialize(@io : IO, @max_batch_size : Int32 = MAX_BATCH_SIZE, @timeout : Time::Span = BATCH_TIMEOUT)
        @buffers = Array(Bytes).new
        @total_size = 0
        @mutex = Mutex.new
        @stats = IOStats.new
      end

      # Add data to batch
      def add(data : Bytes) : Nil
        @mutex.synchronize do
          @buffers << data
          @total_size += data.size

          # Flush if batch is full or too large
          if @buffers.size >= @max_batch_size || @total_size >= LARGE_BUFFER_SIZE
            flush_locked
          end
        end
      end

      # Flush all batched data
      def flush : Nil
        @mutex.synchronize { flush_locked }
      end

      private def flush_locked : Nil
        return if @buffers.empty?

        start_time = Time.monotonic

        # Optimize for single buffer case
        if @buffers.size == 1
          @io.write(@buffers.first)
        else
          # Combine small buffers to reduce syscalls
          combined = Bytes.new(@total_size)
          offset = 0

          @buffers.each do |buffer|
            combined[offset, buffer.size].copy_from(buffer)
            offset += buffer.size
          end

          @io.write(combined)
        end

        @stats.record_write(@total_size, Time.monotonic - start_time)
        @stats.batches_flushed += 1

        @buffers.clear
        @total_size = 0
      end
    end

    # Socket buffer optimization
    module SocketOptimizer
      # Optimize socket for HTTP/2 performance
      def self.optimize(io : IO) : Nil
        # Only optimize if it's a real socket
        if io.responds_to?(:tcp_nodelay=)
          # Set socket options for better performance
          io.tcp_nodelay = true # Disable Nagle's algorithm
        end

        if io.responds_to?(:recv_buffer_size=)
          # Set larger socket buffers for better throughput
          io.recv_buffer_size = DEFAULT_RECV_BUFFER
          io.send_buffer_size = DEFAULT_SEND_BUFFER
        end

        if io.responds_to?(:keepalive=)
          # Keep-alive settings for connection health
          io.keepalive = true
        end

        # Platform-specific optimizations would go here
        # (e.g., SO_REUSEPORT, TCP_FASTOPEN, etc.)
      end

      # Get optimal buffer size based on IO state
      def self.optimal_buffer_size(io : IO) : Int32
        # Default to medium buffer size for most I/O
        MEDIUM_BUFFER_SIZE
      end
    end

    # I/O statistics tracking
    class IOStats
      property batches_flushed : Int32
      property bytes_read : Int64
      property bytes_written : Int64
      property read_operations : Int32
      property total_read_time : Time::Span
      property total_write_time : Time::Span
      property write_operations : Int32

      def initialize
        @bytes_read = 0_i64
        @bytes_written = 0_i64
        @read_operations = 0
        @write_operations = 0
        @batches_flushed = 0
        @total_read_time = Time::Span.zero
        @total_write_time = Time::Span.zero
      end

      def record_read(bytes : Int32, duration : Time::Span) : Nil
        @bytes_read += bytes
        @read_operations += 1
        @total_read_time += duration
      end

      def record_write(bytes : Int32, duration : Time::Span) : Nil
        @bytes_written += bytes
        @write_operations += 1
        @total_write_time += duration
      end

      def average_read_size : Float64
        @read_operations > 0 ? @bytes_read.to_f / @read_operations : 0.0
      end

      def average_write_size : Float64
        @write_operations > 0 ? @bytes_written.to_f / @write_operations : 0.0
      end

      def read_throughput : Float64
        @total_read_time.total_seconds > 0 ? @bytes_read / @total_read_time.total_seconds : 0.0
      end

      def write_throughput : Float64
        @total_write_time.total_seconds > 0 ? @bytes_written / @total_write_time.total_seconds : 0.0
      end
    end
  end
end
