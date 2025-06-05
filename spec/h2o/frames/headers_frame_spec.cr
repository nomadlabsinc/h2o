require "../../spec_helper"

describe H2O::HeadersFrame do
  describe "#initialize" do
    it "creates a headers frame without flags" do
      header_block = "test headers".to_slice
      frame = H2O::HeadersFrame.new(1_u32, header_block)

      frame.stream_id.should eq(1_u32)
      frame.header_block.should eq(header_block)
      frame.length.should eq(header_block.size)
      frame.frame_type.should eq(H2O::FrameType::Headers)
      frame.flags.should eq(0_u8)
    end

    it "creates a headers frame with END_STREAM flag" do
      header_block = "test headers".to_slice
      frame = H2O::HeadersFrame.new(1_u32, header_block, H2O::HeadersFrame::FLAG_END_STREAM)

      frame.end_stream?.should be_true
    end

    it "creates a headers frame with END_HEADERS flag" do
      header_block = "test headers".to_slice
      frame = H2O::HeadersFrame.new(1_u32, header_block, H2O::HeadersFrame::FLAG_END_HEADERS)

      frame.end_headers?.should be_true
    end

    it "creates a headers frame with PADDED flag" do
      header_block = "test headers".to_slice
      padding_length = 5_u8
      frame = H2O::HeadersFrame.new(1_u32, header_block, H2O::HeadersFrame::FLAG_PADDED, padding_length)

      frame.padded?.should be_true
      frame.padding_length.should eq(padding_length)
      frame.length.should eq(header_block.size + 1 + padding_length)
    end

    it "creates a headers frame with PRIORITY flag" do
      header_block = "test headers".to_slice
      flags = H2O::HeadersFrame::FLAG_PRIORITY
      priority_dependency = 2_u32
      priority_weight = 10_u8
      frame = H2O::HeadersFrame.new(1_u32, header_block, flags, 0_u8, false, priority_dependency, priority_weight)

      frame.priority?.should be_true
      frame.priority_dependency.should eq(priority_dependency)
      frame.priority_weight.should eq(priority_weight)
      frame.length.should eq(header_block.size + 5)
    end

    it "creates a headers frame with all flags" do
      header_block = "test headers".to_slice
      padding_length = 3_u8
      flags = H2O::HeadersFrame::FLAG_END_STREAM | H2O::HeadersFrame::FLAG_END_HEADERS |
              H2O::HeadersFrame::FLAG_PADDED | H2O::HeadersFrame::FLAG_PRIORITY
      priority_dependency = 2_u32
      priority_weight = 15_u8

      frame = H2O::HeadersFrame.new(1_u32, header_block, flags, padding_length, true, priority_dependency, priority_weight)

      frame.end_stream?.should be_true
      frame.end_headers?.should be_true
      frame.padded?.should be_true
      frame.priority?.should be_true
      frame.priority_exclusive.should be_true
      frame.length.should eq(header_block.size + 1 + 5 + padding_length)
    end

    it "raises error for zero stream ID" do
      header_block = "test headers".to_slice
      expect_raises(H2O::FrameError, "HEADERS frame must have non-zero stream ID") do
        H2O::HeadersFrame.new(0_u32, header_block)
      end
    end
  end

  describe "#from_payload" do
    it "creates frame from payload without flags" do
      header_block = "test headers".to_slice
      frame = H2O::HeadersFrame.from_payload(header_block.size.to_u32, 0_u8, 1_u32, header_block)

      frame.header_block.should eq(header_block)
      frame.padded?.should be_false
      frame.priority?.should be_false
    end

    it "creates frame from payload with padding" do
      original_headers = "test headers".to_slice
      padding_length = 4_u8
      payload = Bytes.new(1 + original_headers.size + padding_length)
      payload[0] = padding_length
      payload[1, original_headers.size].copy_from(original_headers)

      frame = H2O::HeadersFrame.from_payload(payload.size.to_u32, H2O::HeadersFrame::FLAG_PADDED, 1_u32, payload)

      frame.header_block.should eq(original_headers)
      frame.padding_length.should eq(padding_length)
      frame.padded?.should be_true
    end

    it "creates frame from payload with priority" do
      original_headers = "test headers".to_slice
      priority_dependency = 0x1234_u32
      priority_weight = 42_u8

      payload = Bytes.new(5 + original_headers.size)
      payload[0] = (priority_dependency >> 24).to_u8
      payload[1] = (priority_dependency >> 16).to_u8
      payload[2] = (priority_dependency >> 8).to_u8
      payload[3] = priority_dependency.to_u8
      payload[4] = priority_weight
      payload[5, original_headers.size].copy_from(original_headers) if original_headers.size > 0

      frame = H2O::HeadersFrame.from_payload(payload.size.to_u32, H2O::HeadersFrame::FLAG_PRIORITY, 1_u32, payload)

      frame.header_block.should eq(original_headers)
      frame.priority_dependency.should eq(priority_dependency)
      frame.priority_weight.should eq(priority_weight)
      frame.priority?.should be_true
    end
  end

  describe "#payload_to_bytes" do
    it "serializes headers without flags" do
      header_block = "test headers".to_slice
      frame = H2O::HeadersFrame.new(1_u32, header_block)

      payload = frame.payload_to_bytes
      payload.should eq(header_block)
    end

    it "serializes headers with padding" do
      header_block = "test headers".to_slice
      padding_length = 4_u8
      frame = H2O::HeadersFrame.new(1_u32, header_block, H2O::HeadersFrame::FLAG_PADDED, padding_length)

      payload = frame.payload_to_bytes
      payload.size.should eq(1 + header_block.size + padding_length)
      payload[0].should eq(padding_length)
      payload[1, header_block.size].should eq(header_block)
    end

    it "serializes headers with priority" do
      header_block = "test headers".to_slice
      priority_dependency = 0x1234_u32
      priority_weight = 42_u8
      frame = H2O::HeadersFrame.new(1_u32, header_block, H2O::HeadersFrame::FLAG_PRIORITY, 0_u8, false, priority_dependency, priority_weight)

      payload = frame.payload_to_bytes
      payload.size.should eq(5 + header_block.size)

      decoded_dependency = ((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                            (payload[2].to_u32 << 8) | payload[3].to_u32)
      decoded_dependency.should eq(priority_dependency)
      payload[4].should eq(priority_weight)
      payload[5, header_block.size].should eq(header_block) if header_block.size > 0
    end
  end
end
