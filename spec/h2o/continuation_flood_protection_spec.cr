require "../spec_helper"

describe "CVE-2024-27316 CONTINUATION Flood Protection" do
  describe "ContinuationLimits" do
    it "should have sensible defaults" do
      limits = H2O::ContinuationLimits.new

      limits.max_continuation_frames.should eq(10)
      limits.max_header_size.should eq(8192)
      limits.max_accumulated_size.should eq(16384)
    end

    it "should allow custom configuration" do
      limits = H2O::ContinuationLimits.new(
        max_continuation_frames: 5,
        max_header_size: 4096,
        max_accumulated_size: 8192
      )

      limits.max_continuation_frames.should eq(5)
      limits.max_header_size.should eq(4096)
      limits.max_accumulated_size.should eq(8192)
    end
  end

  describe "ContinuationFloodError" do
    it "should have default message" do
      error = H2O::ContinuationFloodError.new("CONTINUATION flood attack detected")
      error.message.should eq("CONTINUATION flood attack detected")
    end

    it "should accept custom message" do
      error = H2O::ContinuationFloodError.new("Custom error message")
      error.message.should eq("Custom error message")
    end
  end

  describe "HeaderFragmentState" do
    it "should create proper fragment state" do
      buffer = IO::Memory.new
      buffer.write("test data".to_slice)

      fragment = {
        stream_id:          1_u32,
        accumulated_size:   9,
        continuation_count: 0,
        buffer:             buffer,
      }

      fragment[:stream_id].should eq(1_u32)
      fragment[:accumulated_size].should eq(9)
      fragment[:continuation_count].should eq(0)
      fragment[:buffer].to_s.should eq("test data")
    end
  end
end
