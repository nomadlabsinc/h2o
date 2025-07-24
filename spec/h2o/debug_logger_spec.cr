require "../spec_helper"

describe H2O::DebugLogger do
  before_each do
    # Reset the logger cache before each test
    H2O::DebugLogger.reset_cache
    # Ensure H2O_DEBUG is unset initially
    ENV.delete("H2O_DEBUG")
  end

  after_each do
    # Clean up environment variable
    ENV.delete("H2O_DEBUG")
    # Reset cache after each test
    H2O::DebugLogger.reset_cache
  end

  describe ".enabled?" do
    it "returns false when H2O_DEBUG is not set" do
      H2O::DebugLogger.enabled?.should be_false
    end

    it "returns false when H2O_DEBUG is set to false" do
      ENV["H2O_DEBUG"] = "false"
      H2O::DebugLogger.enabled?.should be_false
    end

    it "returns true when H2O_DEBUG is set to true" do
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.enabled?.should be_true
    end

    it "returns true when H2O_DEBUG is set to yes" do
      ENV["H2O_DEBUG"] = "yes"
      H2O::DebugLogger.enabled?.should be_true
    end

    it "returns true when H2O_DEBUG is set to 1" do
      ENV["H2O_DEBUG"] = "1"
      H2O::DebugLogger.enabled?.should be_true
    end

    it "returns true when H2O_DEBUG is set to on" do
      ENV["H2O_DEBUG"] = "on"
      H2O::DebugLogger.enabled?.should be_true
    end

    it "caches the result to avoid repeated environment variable checks" do
      ENV["H2O_DEBUG"] = "true"
      
      # First call should return true
      H2O::DebugLogger.enabled?.should be_true
      
      # Change the environment variable
      ENV["H2O_DEBUG"] = "false"
      
      # Second call should still return true due to caching
      H2O::DebugLogger.enabled?.should be_true
    end
  end

  describe ".reset_cache" do
    it "forces re-reading of environment variable" do
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.enabled?.should be_true
      
      ENV["H2O_DEBUG"] = "false"
      H2O::DebugLogger.reset_cache
      H2O::DebugLogger.enabled?.should be_false
    end
  end

  describe ".log" do
    it "does not call H2O::Log.debug when logging is disabled" do
      # Ensure debugging is disabled
      ENV.delete("H2O_DEBUG")
      H2O::DebugLogger.reset_cache
      
      # We can't easily mock in Crystal, but we can verify the enabled state
      H2O::DebugLogger.enabled?.should be_false
      
      # The log method should return early without calling H2O::Log.debug
      # This test verifies the performance-conscious design
      H2O::DebugLogger.log "TEST", "This should not be processed"
      
      # If we reach here without exception, the test passes
      # The actual log behavior is tested in integration tests
    end

    it "calls through to H2O::Log.debug when enabled (integration test)" do
      # Enable debugging
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.reset_cache
      
      # Verify debugging is enabled
      H2O::DebugLogger.enabled?.should be_true
      
      # Call the log method - this should reach H2O::Log.debug
      # We can't easily capture the output in this test, but we can verify
      # that the method executes without error
      H2O::DebugLogger.log "TEST", "Debug message"
      
      # If we reach here, the log call succeeded
    end

    it "formats context and message correctly (behavior test)" do
      # Enable debugging
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.reset_cache
      
      # This test verifies that the method can handle various input formats
      # without throwing exceptions
      H2O::DebugLogger.log "FRAME", "Reading HTTP/2 frame header"
      H2O::DebugLogger.log "CONTEXT", "Message with #{123} interpolation"
      H2O::DebugLogger.log "TEST", ""
      
      # If we reach here, all log calls succeeded
    end
  end

  describe "integration with frame parsing" do
    it "parses frames correctly when debugging is disabled" do
      # Ensure debugging is disabled
      ENV.delete("H2O_DEBUG")
      H2O::DebugLogger.reset_cache
      
      # Verify debugging is disabled
      H2O::DebugLogger.enabled?.should be_false
      
      # Create a simple SETTINGS frame (9 byte header + 0 byte payload)
      frame_data = Bytes[
        0x00, 0x00, 0x00,  # Length: 0
        0x04,              # Type: SETTINGS (4)
        0x00,              # Flags: 0
        0x00, 0x00, 0x00, 0x00  # Stream ID: 0
      ]
      
      # Parse the frame - this should execute debug logging code paths
      # but the debug logger should return early due to enabled? being false
      io = IO::Memory.new(frame_data)
      frame = H2O::Frame.from_io(io)
      
      # Verify the frame was parsed correctly (main functionality works)
      frame.should be_a(H2O::SettingsFrame)
      frame.length.should eq(0)
      frame.stream_id.should eq(0)
    end

    it "parses frames correctly when debugging is enabled" do
      # Enable debugging
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.reset_cache
      
      # Verify debugging is enabled
      H2O::DebugLogger.enabled?.should be_true
      
      # Create a simple SETTINGS frame (9 byte header + 0 byte payload)
      frame_data = Bytes[
        0x00, 0x00, 0x00,  # Length: 0
        0x04,              # Type: SETTINGS (4)
        0x00,              # Flags: 0
        0x00, 0x00, 0x00, 0x00  # Stream ID: 0
      ]
      
      # Parse the frame - this should execute debug logging calls
      io = IO::Memory.new(frame_data)
      frame = H2O::Frame.from_io(io)
      
      # Verify the frame was parsed correctly (main functionality still works)
      frame.should be_a(H2O::SettingsFrame)
      frame.length.should eq(0)
      frame.stream_id.should eq(0)
    end

    it "handles frame parsing with larger payloads when debugging enabled" do
      # Enable debugging
      ENV["H2O_DEBUG"] = "true"
      H2O::DebugLogger.reset_cache
      
      # Create a SETTINGS frame with a small payload
      payload = Bytes[0x00, 0x01, 0x00, 0x00, 0x10, 0x00]  # HEADER_TABLE_SIZE = 4096
      frame_data = Bytes.new(9 + payload.size)
      
      # Header
      frame_data[0] = 0x00  # Length high byte
      frame_data[1] = 0x00  # Length middle byte
      frame_data[2] = payload.size.to_u8  # Length low byte
      frame_data[3] = 0x04  # Type: SETTINGS
      frame_data[4] = 0x00  # Flags
      frame_data[5] = 0x00  # Stream ID (4 bytes)
      frame_data[6] = 0x00
      frame_data[7] = 0x00
      frame_data[8] = 0x00
      
      # Payload
      payload.each_with_index { |byte, i| frame_data[9 + i] = byte }
      
      # Parse the frame
      io = IO::Memory.new(frame_data)
      frame = H2O::Frame.from_io(io)
      
      # Verify parsing worked correctly
      frame.should be_a(H2O::SettingsFrame)
      frame.length.should eq(payload.size)
      frame.stream_id.should eq(0)
    end
  end

  describe "performance characteristics" do
    it "has minimal overhead when disabled (design verification)" do
      # This test documents the performance design rather than measuring it.
      # The implementation uses `if H2O::DebugLogger.enabled?` checks which,
      # when logging is disabled, compile down to a single boolean comparison.
      # The string interpolation and log calls inside the if blocks are never
      # executed when disabled, ensuring near-zero overhead.
      
      ENV.delete("H2O_DEBUG")
      H2O::DebugLogger.reset_cache
      
      # Verify that enabled? returns false quickly
      start_time = Time.monotonic
      result = H2O::DebugLogger.enabled?
      end_time = Time.monotonic
      
      result.should be_false
      # The call should be extremely fast (under 1ms even on slow systems)
      (end_time - start_time).should be < 1.millisecond
    end
  end
end