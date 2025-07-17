require "../spec_helper"

describe H2O::IOOptimizer do
  describe "ZeroCopyReader" do
    it "performs efficient file transfers" do
      test_content = "Hello, Zero-Copy World!" * 1000
      temp_file = File.tempfile("zero_copy_test")

      begin
        temp_file.print(test_content)
        temp_file.close

        output = IO::Memory.new
        mutex = Mutex.new
        reader = H2O::IOOptimizer::ZeroCopyReader.new(output, mutex)

        transferred = reader.transfer_file(temp_file.path, output)

        transferred.should eq(test_content.bytesize)
        output.to_s.should eq(test_content)
        reader.stats.bytes_read.should eq(test_content.bytesize)
      ensure
        temp_file.delete
      end
    end

    it "handles empty files gracefully" do
      temp_file = File.tempfile("empty_test")

      begin
        temp_file.close

        output = IO::Memory.new
        mutex = Mutex.new
        reader = H2O::IOOptimizer::ZeroCopyReader.new(output, mutex)

        transferred = reader.transfer_file(temp_file.path, output)

        transferred.should eq(0)
        output.to_s.should be_empty
      ensure
        temp_file.delete
      end
    end
  end

  describe "ZeroCopyWriter" do
    it "serves files efficiently" do
      test_content = "File serving test content" * 500
      temp_file = File.tempfile("serve_test")

      begin
        temp_file.print(test_content)
        temp_file.close

        output = IO::Memory.new
        writer = H2O::IOOptimizer::ZeroCopyWriter.new(output)

        served = writer.serve_file(temp_file.path)

        served.should eq(test_content.bytesize)
        output.to_s.should eq(test_content)
        writer.stats.bytes_written.should eq(test_content.bytesize)
      ensure
        temp_file.delete
      end
    end

    it "optimizes small buffer writes with writev" do
      output = IO::Memory.new
      writer = H2O::IOOptimizer::ZeroCopyWriter.new(output)

      buffers = [
        "Hello".to_slice,
        " ".to_slice,
        "World".to_slice,
      ]

      total_written = writer.writev(buffers)

      total_written.should eq(11)
      output.to_s.should eq("Hello World")
      writer.stats.write_operations.should eq(1) # Should be combined into single write
    end

    it "handles large buffer writes with writev" do
      output = IO::Memory.new
      writer = H2O::IOOptimizer::ZeroCopyWriter.new(output)

      # Create buffers that exceed small buffer threshold
      large_buffers = (0..10).map { |i| ("Data#{i}" * 1000).to_slice }

      total_written = writer.writev(large_buffers)
      expected_size = large_buffers.sum(&.size)

      total_written.should eq(expected_size)
      output.to_s.size.should eq(expected_size)
      writer.stats.write_operations.should eq(1) # All writes tracked as one operation
    end
  end

  describe "BatchedWriter" do
    it "batches small writes efficiently" do
      output = IO::Memory.new
      batcher = H2O::IOOptimizer::BatchedWriter.new(output, max_batch_size: 3)

      # Add some small writes
      batcher.add("Hello".to_slice)
      batcher.add(" ".to_slice)
      batcher.add("World".to_slice)

      # Should auto-flush when batch is full
      output.to_s.should eq("Hello World")
      batcher.stats.batches_flushed.should eq(1)
    end

    it "flushes when total size exceeds threshold" do
      output = IO::Memory.new
      batcher = H2O::IOOptimizer::BatchedWriter.new(output)

      # Add data that exceeds LARGE_BUFFER_SIZE
      large_data = "X" * (H2O::IOOptimizer::LARGE_BUFFER_SIZE + 1)
      batcher.add(large_data.to_slice)

      # Should auto-flush due to size
      output.to_s.should eq(large_data)
      batcher.stats.batches_flushed.should eq(1)
    end

    it "handles manual flush correctly" do
      output = IO::Memory.new
      batcher = H2O::IOOptimizer::BatchedWriter.new(output)

      batcher.add("Test".to_slice)
      output.to_s.should be_empty # Not flushed yet

      batcher.flush
      output.to_s.should eq("Test")
      batcher.stats.batches_flushed.should eq(1)
    end
  end

  describe "SocketOptimizer" do
    it "optimizes socket settings when supported" do
      # Create a mock IO that responds to socket methods
      mock_socket = MockSocket.new

      H2O::IOOptimizer::SocketOptimizer.optimize(mock_socket)

      mock_socket.tcp_nodelay_set.should be_true
      mock_socket.recv_buffer_size.should eq(H2O::IOOptimizer::DEFAULT_RECV_BUFFER)
      mock_socket.send_buffer_size.should eq(H2O::IOOptimizer::DEFAULT_SEND_BUFFER)
      mock_socket.keepalive_set.should be_true
    end

    it "handles non-socket IO gracefully" do
      regular_io = IO::Memory.new

      # Should not raise error when optimizing non-socket IO
      H2O::IOOptimizer::SocketOptimizer.optimize(regular_io)

      # Should return reasonable buffer size
      size = H2O::IOOptimizer::SocketOptimizer.optimal_buffer_size(regular_io)
      size.should eq(H2O::IOOptimizer::MEDIUM_BUFFER_SIZE)
    end
  end

  describe "IOStats" do
    it "tracks read and write statistics accurately" do
      stats = H2O::IOOptimizer::IOStats.new

      # Record some operations
      stats.record_read(100, 1.millisecond)
      stats.record_read(200, 2.milliseconds)
      stats.record_write(150, 1.5.milliseconds)

      stats.bytes_read.should eq(300)
      stats.bytes_written.should eq(150)
      stats.read_operations.should eq(2)
      stats.write_operations.should eq(1)

      stats.average_read_size.should eq(150.0)
      stats.average_write_size.should eq(150.0)

      # Check throughput calculations
      stats.read_throughput.should be > 0.0
      stats.write_throughput.should be > 0.0
    end
  end
end

# Mock socket class for testing socket optimization
class MockSocket < IO
  property tcp_nodelay_set : Bool = false
  property recv_buffer_size : Int32 = 0
  property send_buffer_size : Int32 = 0
  property keepalive_set : Bool = false

  def tcp_nodelay=(value : Bool)
    @tcp_nodelay_set = value
  end

  def recv_buffer_size=(size : Int32)
    @recv_buffer_size = size
  end

  def send_buffer_size=(size : Int32)
    @send_buffer_size = size
  end

  def keepalive=(value : Bool)
    @keepalive_set = value
  end

  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
  end
end
