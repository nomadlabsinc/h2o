require "../../spec_helper"

# Mock TcpSocket for testing
class MockTcpSocket < H2O::TcpSocket
  def initialize(@underlying_io : IO)
    @closed = false
  end
  
  def to_io : IO
    @underlying_io
  end
  
  def close : Nil
    @closed = true
    @underlying_io.close if @underlying_io.responds_to?(:close)
  end
  
  def closed? : Bool
    @closed
  end
end

describe "H2O::H2::Client Flow Control" do
  describe "WINDOW_UPDATE frame sending" do
    it "sends WINDOW_UPDATE frames after consuming DATA frames" do
      # Create a mock socket for testing
      socket_pair = UNIXSocket.pair
      client_socket, server_socket = socket_pair[0], socket_pair[1]
      
      # Create H2::Client with mock socket
      client = H2O::H2::Client.allocate
      client.initialize_for_testing(client_socket)
      
      # Send initial HTTP/2 preface and settings
      server_socket.write(H2O::CONNECTION_PREFACE)
      settings_frame = H2O::SettingsFrame.new
      server_socket.write(settings_frame.to_bytes)
      
      # Create a DATA frame with some content
      data_content = "Hello HTTP/2 Flow Control!"
      data_frame = H2O::DataFrame.new(1_u32, data_content.to_slice)
      data_frame.set_end_stream
      
      # Start request in fiber to handle async I/O
      response_channel = Channel(H2O::Response).new
      
      spawn do
        response = client.request("GET", "/test")
        response_channel.send(response)
      end
      
      # Read and validate the outgoing request frames
      request_frames = read_frames_from_socket(server_socket, 2) # HEADERS + potential WINDOW_UPDATE
      
      # Send response: HEADERS frame followed by DATA frame
      headers_frame = create_response_headers_frame(1_u32, 200)
      server_socket.write(headers_frame.to_bytes)
      server_socket.write(data_frame.to_bytes)
      
      # Read any WINDOW_UPDATE frames sent by client after consuming DATA
      window_update_frames = read_frames_from_socket(server_socket, 2, timeout: 1.0) # Expect 2 WINDOW_UPDATE frames
      
      # Verify client sent WINDOW_UPDATE frames
      window_update_frames.size.should eq(2)
      
      # First should be stream-level WINDOW_UPDATE
      stream_update = window_update_frames[0].as(H2O::WindowUpdateFrame)
      stream_update.stream_id.should eq(1_u32)
      stream_update.window_size_increment.should eq(data_content.bytesize.to_u32)
      
      # Second should be connection-level WINDOW_UPDATE
      connection_update = window_update_frames[1].as(H2O::WindowUpdateFrame)
      connection_update.stream_id.should eq(0_u32)
      connection_update.window_size_increment.should eq(data_content.bytesize.to_u32)
      
      # Verify response is received correctly
      response = response_channel.receive
      response.status.should eq(200)
      response.body.should eq(data_content)
      
      socket_pair.each(&.close)
    end
    
    it "handles multiple DATA frames with cumulative WINDOW_UPDATE" do
      socket_pair = UNIXSocket.pair
      client_socket, server_socket = socket_pair[0], socket_pair[1]
      
      client = H2O::H2::Client.allocate
      client.initialize_for_testing(client_socket)
      
      # Send initial HTTP/2 preface and settings
      server_socket.write(H2O::CONNECTION_PREFACE)
      settings_frame = H2O::SettingsFrame.new
      server_socket.write(settings_frame.to_bytes)
      
      response_channel = Channel(H2O::Response).new
      
      spawn do
        response = client.request("GET", "/test")
        response_channel.send(response)
      end
      
      # Read request frames
      read_frames_from_socket(server_socket, 2)
      
      # Send response with multiple DATA frames
      headers_frame = create_response_headers_frame(1_u32, 200)
      server_socket.write(headers_frame.to_bytes)
      
      data_chunks = ["Chunk 1", "Chunk 2", "Chunk 3"]
      total_size = 0
      
      data_chunks.each_with_index do |chunk, index|
        is_last = (index == data_chunks.size - 1)
        data_frame = H2O::DataFrame.new(1_u32, chunk.to_slice)
        data_frame.set_end_stream if is_last
        server_socket.write(data_frame.to_bytes)
        total_size += chunk.bytesize
        
        # Read WINDOW_UPDATE frames after each DATA frame
        window_updates = read_frames_from_socket(server_socket, 2, timeout: 0.5)
        window_updates.size.should eq(2)
        
        # Verify increments match chunk size
        stream_update = window_updates[0].as(H2O::WindowUpdateFrame)
        stream_update.window_size_increment.should eq(chunk.bytesize.to_u32)
        
        connection_update = window_updates[1].as(H2O::WindowUpdateFrame)
        connection_update.window_size_increment.should eq(chunk.bytesize.to_u32)
      end
      
      response = response_channel.receive
      response.status.should eq(200)
      response.body.should eq(data_chunks.join)
      
      socket_pair.each(&.close)
    end
  end
  
  describe "Flow control window management" do
    it "properly tracks connection-level flow control windows" do
      socket_pair = UNIXSocket.pair
      client_socket, server_socket = socket_pair[0], socket_pair[1]
      
      client = H2O::H2::Client.allocate
      client.initialize_for_testing(client_socket)
      
      # Initial connection window should be 65535
      client.connection_window_size.should eq(65535)
      
      # Send initial preface
      server_socket.write(H2O::CONNECTION_PREFACE)
      settings_frame = H2O::SettingsFrame.new
      server_socket.write(settings_frame.to_bytes)
      
      response_channel = Channel(H2O::Response).new
      
      spawn do
        response = client.request("GET", "/test")
        response_channel.send(response)
      end
      
      # Read request
      read_frames_from_socket(server_socket, 2)
      
      # Send response with significant data to consume window
      headers_frame = create_response_headers_frame(1_u32, 200)
      server_socket.write(headers_frame.to_bytes)
      
      large_data = "X" * 32000  # Consume significant window space
      data_frame = H2O::DataFrame.new(1_u32, large_data.to_slice)
      data_frame.set_end_stream
      server_socket.write(data_frame.to_bytes)
      
      # Read WINDOW_UPDATE frames
      window_updates = read_frames_from_socket(server_socket, 2)
      
      # Connection window should remain healthy due to WINDOW_UPDATE
      connection_update = window_updates[1].as(H2O::WindowUpdateFrame)
      connection_update.window_size_increment.should eq(32000_u32)
      
      response = response_channel.receive
      response.status.should eq(200)
      
      socket_pair.each(&.close)
    end
    
    it "cleans up stream flow control on stream end" do
      socket_pair = UNIXSocket.pair
      client_socket, server_socket = socket_pair[0], socket_pair[1]
      
      client = H2O::H2::Client.allocate
      client.initialize_for_testing(client_socket)
      
      # Send initial preface
      server_socket.write(H2O::CONNECTION_PREFACE)
      settings_frame = H2O::SettingsFrame.new
      server_socket.write(settings_frame.to_bytes)
      
      response_channel = Channel(H2O::Response).new
      
      spawn do
        response = client.request("GET", "/test")
        response_channel.send(response)
      end
      
      # Read request
      read_frames_from_socket(server_socket, 2)
      
      # Send response
      headers_frame = create_response_headers_frame(1_u32, 200)
      server_socket.write(headers_frame.to_bytes)
      
      data_frame = H2O::DataFrame.new(1_u32, "test".to_slice)
      data_frame.set_end_stream
      server_socket.write(data_frame.to_bytes)
      
      # Read WINDOW_UPDATE frames
      read_frames_from_socket(server_socket, 2)
      
      response = response_channel.receive
      response.status.should eq(200)
      
      # Stream flow control should be cleaned up
      client.stream_flow_controls.has_key?(1_u32).should be_false
      
      socket_pair.each(&.close)
    end
  end
  
  describe "Connection hang prevention" do
    it "prevents hangs by sending WINDOW_UPDATE for large responses" do
      socket_pair = UNIXSocket.pair
      client_socket, server_socket = socket_pair[0], socket_pair[1]
      
      client = H2O::H2::Client.allocate
      client.initialize_for_testing(client_socket)
      
      # Send initial preface
      server_socket.write(H2O::CONNECTION_PREFACE)
      settings_frame = H2O::SettingsFrame.new
      server_socket.write(settings_frame.to_bytes)
      
      response_channel = Channel(H2O::Response).new
      
      spawn do
        response = client.request("GET", "/large-response")
        response_channel.send(response)
      end
      
      # Read request
      read_frames_from_socket(server_socket, 2)
      
      # Send response headers
      headers_frame = create_response_headers_frame(1_u32, 200)
      server_socket.write(headers_frame.to_bytes)
      
      # Send multiple large DATA frames to simulate scenario that caused hangs
      total_data_sent = 0
      chunk_size = 8192
      num_chunks = 10  # Total: ~80KB, exceeds initial window
      
      num_chunks.times do |i|
        is_last = (i == num_chunks - 1)
        chunk_data = "DATA_CHUNK_#{i}_" + ("X" * (chunk_size - 20))
        
        data_frame = H2O::DataFrame.new(1_u32, chunk_data.to_slice)
        data_frame.set_end_stream if is_last
        server_socket.write(data_frame.to_bytes)
        
        total_data_sent += chunk_data.bytesize
        
        # Each DATA frame should trigger WINDOW_UPDATE frames
        window_updates = read_frames_from_socket(server_socket, 2, timeout: 2.0)
        window_updates.size.should eq(2)
        
        # Verify both stream and connection WINDOW_UPDATE are sent
        stream_update = window_updates[0].as(H2O::WindowUpdateFrame)
        stream_update.stream_id.should eq(1_u32)
        stream_update.window_size_increment.should eq(chunk_data.bytesize.to_u32)
        
        connection_update = window_updates[1].as(H2O::WindowUpdateFrame)
        connection_update.stream_id.should eq(0_u32)
        connection_update.window_size_increment.should eq(chunk_data.bytesize.to_u32)
      end
      
      # Response should complete without timeout
      start_time = Time.monotonic
      response = response_channel.receive
      duration = Time.monotonic - start_time
      
      # Should complete quickly, not timeout (30 seconds)
      duration.total_seconds.should be < 5.0
      response.status.should eq(200)
      response.body.size.should eq(total_data_sent)
      
      socket_pair.each(&.close)
    end
  end
end

# Helper methods for testing
private def read_frames_from_socket(socket : IO, expected_count : Int32, timeout : Float64 = 5.0) : Array(H2O::Frame)
  frames = [] of H2O::Frame
  start_time = Time.monotonic
  
  while frames.size < expected_count
    if Time.monotonic - start_time > timeout.seconds
      break
    end
    
    # Use select to check if data is available
    if IO.select([socket], nil, nil, 0.1)
      if socket.peek.size > 0
        frame = H2O::Frame.from_io(socket)
        frames << frame
      end
    end
  end
  
  frames
end

private def create_response_headers_frame(stream_id : UInt32, status : Int32) : H2O::HeadersFrame
  headers = H2O::Headers.new
  headers[":status"] = status.to_s
  headers["content-type"] = "text/plain"
  
  # Create HPACK encoder to encode headers
  encoder = H2O::HPACK::Encoder.new
  encoded_headers = encoder.encode(headers)
  
  frame = H2O::HeadersFrame.new(stream_id, encoded_headers)
  frame.set_end_headers
  frame
end

# Extension to H2::Client for testing
class H2O::H2::Client
  def initialize_for_testing(socket : IO)
    # Create a mock TcpSocket wrapper for testing
    mock_tcp_socket = MockTcpSocket.new(socket)
    @socket = mock_tcp_socket
    @local_settings = Settings.new
    @remote_settings = Settings.new
    @hpack_encoder = HPACK::Encoder.new
    @hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
    @connection_flow_control = H2O::Connection::FlowControl.new
    @stream_flow_controls = Hash(StreamId, H2O::Stream::FlowControl).new
    @connection_window_size = 65535
    @current_stream_id = 1_u32
    @closed = false
    @request_timeout = 30.seconds
    @connect_timeout = 10.seconds
    @mutex = Mutex.new
    @io_optimization_enabled = false
  end
  
  def connection_window_size
    @connection_window_size
  end
  
  def stream_flow_controls
    @stream_flow_controls
  end
end