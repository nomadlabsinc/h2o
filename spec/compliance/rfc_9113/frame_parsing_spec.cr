require "../../spec_helper"
require "../../support/in_memory_transport"

describe "RFC 9113 Frame Parsing and Serialization" do
  describe "frame format validation" do
    it "validates frame length field against MAX_FRAME_SIZE" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      # Test sending a valid small frame
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      
      stream_id = engine.send_request("GET", "/", headers)
      transport.has_outgoing_data?.should be_true
      
      # All frames should respect length limits
      outgoing = transport.get_outgoing_data
      
      # Parse each frame and verify length field
      offset = 24  # Skip preface
      while offset < outgoing.size - 9  # Need at least frame header
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        
        # RFC 9113: Frame length must not exceed MAX_FRAME_SIZE (default 16384)
        length.should be <= 16384
        
        offset += 9 + length  # Move to next frame
      end
    end
    
    it "validates reserved bits in frame header" do
      # This test ensures we properly handle reserved bits
      # RFC 9113 Section 4.1: Reserved bit must be unset
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      engine.send_request("GET", "/", headers)
      
      outgoing = transport.get_outgoing_data
      
      # Check frames after preface
      offset = 24
      while offset < outgoing.size - 9
        # Stream ID field (bytes 5-8) should have reserved bit (0x80000000) unset
        stream_id_with_reserved = (outgoing[offset + 5].to_u32 << 24) |
                                  (outgoing[offset + 6].to_u32 << 16) |
                                  (outgoing[offset + 7].to_u32 << 8) |
                                  outgoing[offset + 8].to_u32
        
        # Reserved bit should be 0
        reserved_bit = (stream_id_with_reserved & 0x80000000_u32) != 0
        reserved_bit.should be_false
        
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        offset += 9 + length
      end
    end
    
    it "validates frame type field values" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      # Send different types of frames
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      
      stream_id = engine.send_request("POST", "/", headers)
      engine.send_data(stream_id, "test data", end_stream: true)
      
      outgoing = transport.get_outgoing_data
      frame_types_seen = Set(UInt8).new
      
      # Parse frames and collect frame types
      offset = 24  # Skip preface
      while offset < outgoing.size - 9
        frame_type = outgoing[offset + 3]
        frame_types_seen << frame_type
        
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        offset += 9 + length
      end
      
      # Should see SETTINGS, HEADERS, and DATA frames
      frame_types_seen.should contain(0x04_u8)  # SETTINGS
      frame_types_seen.should contain(0x01_u8)  # HEADERS  
      frame_types_seen.should contain(0x00_u8)  # DATA
      
      # All frame types should be valid (0-9 in RFC 9113)
      frame_types_seen.each do |frame_type|
        frame_type.should be <= 9_u8
      end
    end
  end
  
  describe "stream ID validation" do
    it "uses odd stream IDs for client-initiated streams" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      
      # Send multiple requests
      stream_ids = Array(UInt32).new
      3.times do
        stream_id = engine.send_request("GET", "/", headers)
        stream_ids << stream_id
      end
      
      # All client stream IDs should be odd
      stream_ids.each do |stream_id|
        (stream_id % 2).should eq(1)  # Odd numbers
      end
      
      # Should be in ascending order
      stream_ids.should eq([1_u32, 3_u32, 5_u32])
    end
    
    it "validates stream ID in outgoing frames" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      stream_id = engine.send_request("GET", "/", headers)
      
      outgoing = transport.get_outgoing_data
      
      # Find HEADERS frame and verify stream ID
      offset = 24  # Skip preface
      while offset < outgoing.size - 9
        frame_type = outgoing[offset + 3]
        
        if frame_type == 0x01_u8  # HEADERS frame
          frame_stream_id = (outgoing[offset + 5].to_u32 << 24) |
                           (outgoing[offset + 6].to_u32 << 16) |
                           (outgoing[offset + 7].to_u32 << 8) |
                           outgoing[offset + 8].to_u32
          
          frame_stream_id.should eq(stream_id)
          break
        end
        
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        offset += 9 + length
      end
    end
  end
  
  describe "flag field validation" do
    it "sets appropriate flags for END_STREAM" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      
      # Send request without body (should have END_STREAM)
      stream_id = engine.send_request("GET", "/", headers)
      
      outgoing = transport.get_outgoing_data
      
      # Find HEADERS frame and check END_STREAM flag
      offset = 24  # Skip preface
      while offset < outgoing.size - 9
        frame_type = outgoing[offset + 3]
        
        if frame_type == 0x01_u8  # HEADERS frame
          flags = outgoing[offset + 4]
          # Should have END_STREAM (0x01) and END_HEADERS (0x04) flags
          (flags & 0x01).should_not eq(0)  # END_STREAM
          (flags & 0x04).should_not eq(0)  # END_HEADERS
          break
        end
        
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        offset += 9 + length
      end
    end
    
    it "handles DATA frame END_STREAM flag correctly" do
      transport = H2O::Test::InMemoryTransport.new
      engine = H2O::ProtocolEngine.new(transport)
      engine.establish_connection
      
      headers = H2O::Headers.new
      headers["host"] = "example.com"
      
      # Send request with body
      stream_id = engine.send_request("POST", "/", headers)
      transport.clear_outgoing_data  # Clear previous frames
      
      # Send data with END_STREAM
      engine.send_data(stream_id, "test payload", end_stream: true)
      
      outgoing = transport.get_outgoing_data
      
      # Find DATA frame and check END_STREAM flag
      offset = 0
      while offset < outgoing.size - 9
        frame_type = outgoing[offset + 3]
        
        if frame_type == 0x00_u8  # DATA frame
          flags = outgoing[offset + 4]
          # Should have END_STREAM flag (0x01)
          (flags & 0x01).should_not eq(0)
          break
        end
        
        length = (outgoing[offset].to_u32 << 16) | 
                 (outgoing[offset + 1].to_u32 << 8) | 
                 outgoing[offset + 2].to_u32
        offset += 9 + length
      end
    end
  end
end