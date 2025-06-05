require "../../spec_helper"

describe H2O::PushPromiseFrame do
  describe "#initialize" do
    it "creates a push promise frame without flags" do
      promised_stream_id = 3_u32
      header_block = "test headers".to_slice
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block)

      frame.stream_id.should eq(1_u32)
      frame.promised_stream_id.should eq(promised_stream_id)
      frame.header_block.should eq(header_block)
      frame.length.should eq(4 + header_block.size)
      frame.frame_type.should eq(H2O::FrameType::PushPromise)
    end

    it "creates a push promise frame with END_HEADERS flag" do
      promised_stream_id = 3_u32
      header_block = "test headers".to_slice
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block, true)

      frame.end_headers?.should be_true
    end

    it "creates a push promise frame with PADDED flag" do
      promised_stream_id = 3_u32
      header_block = "test headers".to_slice
      padding_length = 5_u8
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block, false, padding_length)

      frame.padded?.should be_true
      frame.padding_length.should eq(padding_length)
      frame.length.should eq(4 + 1 + header_block.size + padding_length)
    end

    it "creates a push promise frame with both flags" do
      promised_stream_id = 3_u32
      header_block = "test headers".to_slice
      padding_length = 3_u8
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block, true, padding_length)

      frame.end_headers?.should be_true
      frame.padded?.should be_true
      frame.padding_length.should eq(padding_length)
      frame.length.should eq(4 + 1 + header_block.size + padding_length)
    end

    it "raises error for zero stream ID" do
      promised_stream_id = 3_u32
      header_block = "test headers".to_slice
      expect_raises(H2O::FrameError, "PUSH_PROMISE frame must have non-zero stream ID") do
        H2O::PushPromiseFrame.new(0_u32, promised_stream_id, header_block)
      end
    end

    it "masks reserved bit in promised stream ID" do
      promised_stream_id = 0x80000003_u32 # Has reserved bit set
      header_block = "test headers".to_slice
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block)

      frame.promised_stream_id.should eq(0x3_u32) # Reserved bit should be masked
    end
  end

  describe "#from_payload" do
    it "creates frame from payload without padding" do
      promised_stream_id = 5_u32
      header_block = "test headers".to_slice
      payload = Bytes.new(4 + header_block.size)
      payload[0] = (promised_stream_id >> 24).to_u8
      payload[1] = (promised_stream_id >> 16).to_u8
      payload[2] = (promised_stream_id >> 8).to_u8
      payload[3] = promised_stream_id.to_u8
      payload[4, header_block.size].copy_from(header_block)

      frame = H2O::PushPromiseFrame.from_payload(payload.size.to_u32, 0_u8, 1_u32, payload)

      frame.promised_stream_id.should eq(promised_stream_id)
      frame.header_block.should eq(header_block)
      frame.padded?.should be_false
    end

    it "creates frame from payload with padding" do
      promised_stream_id = 5_u32
      header_block = "test headers".to_slice
      padding_length = 3_u8
      payload = Bytes.new(1 + 4 + header_block.size + padding_length)
      payload[0] = padding_length
      payload[1] = (promised_stream_id >> 24).to_u8
      payload[2] = (promised_stream_id >> 16).to_u8
      payload[3] = (promised_stream_id >> 8).to_u8
      payload[4] = promised_stream_id.to_u8
      payload[5, header_block.size].copy_from(header_block)

      frame = H2O::PushPromiseFrame.from_payload(payload.size.to_u32, H2O::PushPromiseFrame::FLAG_PADDED, 1_u32, payload)

      frame.promised_stream_id.should eq(promised_stream_id)
      frame.header_block.should eq(header_block)
      frame.padding_length.should eq(padding_length)
      frame.padded?.should be_true
    end

    it "raises error for zero stream ID" do
      promised_stream_id = 5_u32
      header_block = "test headers".to_slice
      payload = Bytes.new(4 + header_block.size)

      expect_raises(H2O::FrameError, "PUSH_PROMISE frame must have non-zero stream ID") do
        H2O::PushPromiseFrame.from_payload(payload.size.to_u32, 0_u8, 0_u32, payload)
      end
    end

    it "raises error for insufficient payload size" do
      payload = Bytes.new(3) # Less than 4 bytes required

      expect_raises(H2O::FrameError, "PUSH_PROMISE frame must have at least 4 bytes") do
        H2O::PushPromiseFrame.from_payload(payload.size.to_u32, 0_u8, 1_u32, payload)
      end
    end
  end

  describe "#payload_to_bytes" do
    it "serializes push promise without padding" do
      promised_stream_id = 5_u32
      header_block = "test headers".to_slice
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block)

      payload = frame.payload_to_bytes
      payload.size.should eq(4 + header_block.size)

      decoded_stream_id = ((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                           (payload[2].to_u32 << 8) | payload[3].to_u32)
      decoded_stream_id.should eq(promised_stream_id)
      payload[4, header_block.size].should eq(header_block)
    end

    it "serializes push promise with padding" do
      promised_stream_id = 5_u32
      header_block = "test headers".to_slice
      padding_length = 4_u8
      frame = H2O::PushPromiseFrame.new(1_u32, promised_stream_id, header_block, false, padding_length)

      payload = frame.payload_to_bytes
      payload.size.should eq(1 + 4 + header_block.size + padding_length)
      payload[0].should eq(padding_length)

      decoded_stream_id = ((payload[1].to_u32 << 24) | (payload[2].to_u32 << 16) |
                           (payload[3].to_u32 << 8) | payload[4].to_u32)
      decoded_stream_id.should eq(promised_stream_id)
      payload[5, header_block.size].should eq(header_block)
    end
  end
end
