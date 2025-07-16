require "../spec_helper"
require "../support/in_memory_transport"

describe "H2O IoAdapter Implementations" do
  describe "InMemoryTransport" do
    it "should read and write data correctly" do
      transport = H2O::Test::InMemoryTransport.new
      
      # Initially no data available
      transport.read_bytes(100).should be_nil
      transport.has_incoming_data?.should be_false
      transport.has_outgoing_data?.should be_false
      
      # Inject some data and read it
      test_data = "Hello, HTTP/2!".to_slice
      transport.inject_incoming_data(test_data)
      transport.has_incoming_data?.should be_true
      
      # Read the data back
      read_data = transport.read_bytes(100)
      read_data.should_not be_nil
      read_data.not_nil!.should eq(test_data)
      
      # Write some data
      write_data = "Response data".to_slice
      bytes_written = transport.write_bytes(write_data)
      bytes_written.should eq(write_data.size)
      transport.has_outgoing_data?.should be_true
      
      # Verify written data
      outgoing = transport.get_outgoing_data
      outgoing.should eq(write_data)
    end
    
    it "should handle connection closure" do
      transport = H2O::Test::InMemoryTransport.new
      
      # Initially not closed
      transport.closed?.should be_false
      
      # Close the transport
      transport.close
      transport.closed?.should be_true
      
      # Should not be able to read/write after close
      transport.read_bytes(100).should be_nil
      transport.write_bytes("test".to_slice).should eq(0)
    end
    
    it "should trigger callbacks when registered" do
      transport = H2O::Test::InMemoryTransport.new
      data_received = false
      close_received = false
      
      # Register callbacks
      transport.on_data_available do |data|
        data_received = true
      end
      
      transport.on_closed do
        close_received = true
      end
      
      # Inject data - should trigger callback
      transport.inject_incoming_data("test".to_slice)
      data_received.should be_true
      
      # Close - should trigger callback
      transport.close
      close_received.should be_true
    end
    
    it "should provide transport info" do
      transport = H2O::Test::InMemoryTransport.new
      info = transport.transport_info
      
      info["type"].should eq("in_memory")
      info["closed"].should eq("false")
      
      transport.close
      info = transport.transport_info
      info["closed"].should eq("true")
    end
    
    it "should handle partial reads correctly" do
      transport = H2O::Test::InMemoryTransport.new
      
      # Inject larger data
      large_data = "A" * 1000
      transport.inject_incoming_data(large_data.to_slice)
      
      # Read in smaller chunks
      first_chunk = transport.read_bytes(100)
      first_chunk.should_not be_nil
      first_chunk.not_nil!.size.should eq(100)
      
      second_chunk = transport.read_bytes(500)
      second_chunk.should_not be_nil
      second_chunk.not_nil!.size.should eq(500)
      
      # Remaining data
      remaining = transport.read_bytes(1000)
      remaining.should_not be_nil
      remaining.not_nil!.size.should eq(400)  # 1000 - 100 - 500
    end
  end
end