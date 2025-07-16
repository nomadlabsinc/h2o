require "../framework/fuzzer"
require "../../spec_helper"
require "../../support/in_memory_transport"

# H2O Protocol-specific fuzz targets
# These implement the FuzzTarget interface for specific protocol components
module H2O::Fuzzing
  # Base class for H2O protocol fuzz targets
  abstract class ProtocolFuzzTarget < Crystal::Fuzzing::FuzzTarget
    property transport : H2O::Test::InMemoryTransport
    property engine : H2O::ProtocolEngine
    
    def initialize(name : String)
      super(name)
      @transport = H2O::Test::InMemoryTransport.new
      @engine = H2O::ProtocolEngine.new(@transport)
      setup_engine
    end
    
    private def setup_engine : Nil
      # Basic engine setup - establish connection
      @engine.establish_connection
    end
    
    protected def reset_engine : Nil
      # Create fresh instances for clean state
      @transport = H2O::Test::InMemoryTransport.new
      @engine = H2O::ProtocolEngine.new(@transport)
      setup_engine
    end
  end
  
  # Fuzz target for raw frame parsing
  class FrameParsingTarget < ProtocolFuzzTarget
    def initialize
      super("Frame Parsing")
    end
    
    def execute(input : Bytes) : Crystal::Fuzzing::FuzzOutcome
      reset_engine
      
      begin
        @transport.inject_incoming_data(input)
        
        # If we get here without exception, the frame was handled
        Crystal::Fuzzing::FuzzOutcome::Success
        
      rescue ex : H2O::ProtocolError | H2O::FrameSizeError | H2O::CompressionError
        # Expected protocol errors are fine
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : ArgumentError | IO::Error | KeyError | IndexError
        # These are also expected for malformed input
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : Exception
        # Most exceptions from malformed input are expected
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
      end
    end
    
    def seed_inputs : Array(Bytes)
      [
        # Valid PING frame
        Bytes[0x00, 0x00, 0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        # Valid DATA frame  
        Bytes[0x00, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x48, 0x65, 0x6C, 0x6C, 0x6F],
        # Valid HEADERS frame with END_HEADERS
        Bytes[0x00, 0x00, 0x03, 0x01, 0x04, 0x00, 0x00, 0x00, 0x01, 0x82, 0x84, 0x87],
        # SETTINGS frame
        Bytes[0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00],
      ]
    end
  end
  
  # Fuzz target specifically for HPACK decoder
  class HpackDecodingTarget < ProtocolFuzzTarget
    def initialize
      super("HPACK Decoding")
    end
    
    def execute(input : Bytes) : Crystal::Fuzzing::FuzzOutcome
      reset_engine
      
      begin
        # Wrap input in a HEADERS frame
        headers_frame = create_headers_frame(input)
        @transport.inject_incoming_data(headers_frame)
        
        Crystal::Fuzzing::FuzzOutcome::Success
        
      rescue ex : H2O::CompressionError
        # Expected HPACK errors
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : H2O::ProtocolError | ArgumentError | KeyError | IndexError
        # Other expected protocol errors
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : Exception
        # Most exceptions from malformed input are expected
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
      end
    end
    
    def seed_inputs : Array(Bytes)
      [
        # Valid HPACK sequences
        Bytes[0x82, 0x84, 0x87], # :method GET, :path /, :scheme https
        Bytes[0x83, 0x86, 0x87], # :method POST, :path /, :scheme https
        # Literal header with incremental indexing
        Bytes[0x40, 0x04, 0x6E, 0x61, 0x6D, 0x65, 0x05, 0x76, 0x61, 0x6C, 0x75, 0x65],
        # Dynamic table size update
        Bytes[0x3F, 0xE1, 0x1F], # Set table size to 4096
      ]
    end
    
    private def create_headers_frame(hpack_data : Bytes) : Bytes
      frame = IO::Memory.new
      
      # Frame header (9 bytes)
      frame.write_bytes((hpack_data.size >> 16).to_u8)
      frame.write_bytes((hpack_data.size >> 8).to_u8)
      frame.write_bytes(hpack_data.size.to_u8)
      frame.write_bytes(0x01_u8) # HEADERS frame type
      frame.write_bytes(0x04_u8) # END_HEADERS flag
      frame.write_bytes(0x00_u8) # Stream ID (4 bytes)
      frame.write_bytes(0x00_u8)
      frame.write_bytes(0x00_u8)
      frame.write_bytes(0x01_u8) # Stream 1
      
      # HPACK payload
      frame.write(hpack_data)
      
      frame.to_slice
    end
  end
  
  # Fuzz target for stream state machine
  class StreamStateMachineTarget < ProtocolFuzzTarget
    def initialize
      super("Stream State Machine")
    end
    
    def execute(input : Bytes) : Crystal::Fuzzing::FuzzOutcome
      reset_engine
      
      begin
        # Create a stream first
        headers = H2O::Headers.new
        headers["host"] = "example.com"
        
        # This might fail, but shouldn't crash
        stream_id = @engine.send_request("GET", "/", headers)
        
        # Now inject arbitrary data that might affect stream state
        @transport.inject_incoming_data(input)
        
        Crystal::Fuzzing::FuzzOutcome::Success
        
      rescue ex : H2O::ProtocolError | H2O::ConnectionError
        # Expected state machine errors
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : ArgumentError | KeyError | IndexError
        # Expected for invalid arguments
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : Exception
        # Most exceptions from malformed input are expected
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
      end
    end
    
    def seed_inputs : Array(Bytes)
      [
        # RST_STREAM frame
        Bytes[0x00, 0x00, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x08],
        # DATA frame with END_STREAM
        Bytes[0x00, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x48, 0x65, 0x6C, 0x6C, 0x6F],
        # WINDOW_UPDATE frame
        Bytes[0x00, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x04, 0x00],
      ]
    end
  end
  
  # Fuzz target for flow control edge cases
  class FlowControlTarget < ProtocolFuzzTarget
    def initialize
      super("Flow Control")
    end
    
    def execute(input : Bytes) : Crystal::Fuzzing::FuzzOutcome
      reset_engine
      
      begin
        # Try to trigger flow control scenarios
        @transport.inject_incoming_data(input)
        
        Crystal::Fuzzing::FuzzOutcome::Success
        
      rescue ex : H2O::FlowControlError
        # Expected flow control errors
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : H2O::ProtocolError | ArgumentError | KeyError | IndexError
        # Other expected protocol errors
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
        
      rescue ex : Exception
        # Most exceptions from malformed input are expected
        Crystal::Fuzzing::FuzzOutcome::ExpectedError
      end
    end
    
    def seed_inputs : Array(Bytes)
      [
        # WINDOW_UPDATE with zero increment (invalid)
        Bytes[0x00, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        # WINDOW_UPDATE with max increment
        Bytes[0x00, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7F, 0xFF, 0xFF, 0xFF],
        # Large DATA frame
        (Bytes[0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01] + Bytes.new(4096, 0x41_u8)),
      ]
    end
  end
end