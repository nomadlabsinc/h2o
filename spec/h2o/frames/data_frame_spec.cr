require "../../spec_helper"

describe H2O::DataFrame do
  describe "#initialize" do
    it "creates a data frame without flags" do
      data = "Hello World".to_slice
      frame = H2O::DataFrame.new(1_u32, data)

      frame.stream_id.should eq(1_u32)
      frame.data.should eq(data)
      frame.length.should eq(data.size)
      frame.frame_type.should eq(H2O::FrameType::Data)
      frame.flags.should eq(0_u8)
      frame.padding_length.should eq(0_u8)
    end

    it "creates a data frame with END_STREAM flag" do
      data = "Hello World".to_slice
      frame = H2O::DataFrame.new(1_u32, data, H2O::DataFrame::FLAG_END_STREAM)

      frame.end_stream?.should be_true
      frame.flags.should eq(H2O::DataFrame::FLAG_END_STREAM)
    end

    it "creates a data frame with PADDED flag" do
      data = "Hello World".to_slice
      padding_length = 10_u8
      frame = H2O::DataFrame.new(1_u32, data, H2O::DataFrame::FLAG_PADDED, padding_length)

      frame.padded?.should be_true
      frame.padding_length.should eq(padding_length)
      frame.length.should eq(data.size + 1 + padding_length)
    end

    it "creates a data frame with both flags" do
      data = "Hello World".to_slice
      padding_length = 5_u8
      flags = H2O::DataFrame::FLAG_END_STREAM | H2O::DataFrame::FLAG_PADDED
      frame = H2O::DataFrame.new(1_u32, data, flags, padding_length)

      frame.end_stream?.should be_true
      frame.padded?.should be_true
      frame.padding_length.should eq(padding_length)
      frame.length.should eq(data.size + 1 + padding_length)
    end

    it "raises error for zero stream ID" do
      data = "Hello World".to_slice
      expect_raises(H2O::FrameError, "DATA frame must have non-zero stream ID") do
        H2O::DataFrame.new(0_u32, data)
      end
    end
  end

  describe "#from_payload" do
    it "creates frame from payload without padding" do
      data = "Hello World".to_slice
      frame = H2O::DataFrame.from_payload(data.size.to_u32, 0_u8, 1_u32, data)

      frame.data.should eq(data)
      frame.padded?.should be_false
    end

    it "creates frame from payload with padding" do
      original_data = "Hello".to_slice
      padding_length = 3_u8
      payload = Bytes.new(1 + original_data.size + padding_length)
      payload[0] = padding_length
      payload[1, original_data.size].copy_from(original_data)

      frame = H2O::DataFrame.from_payload(payload.size.to_u32, H2O::DataFrame::FLAG_PADDED, 1_u32, payload)

      frame.data.should eq(original_data)
      frame.padding_length.should eq(padding_length)
      frame.padded?.should be_true
    end
  end

  describe "#payload_to_bytes" do
    it "serializes data without padding" do
      data = "Hello World".to_slice
      frame = H2O::DataFrame.new(1_u32, data)

      payload = frame.payload_to_bytes
      payload.should eq(data)
    end

    it "serializes data with padding" do
      data = "Hello".to_slice
      padding_length = 3_u8
      frame = H2O::DataFrame.new(1_u32, data, H2O::DataFrame::FLAG_PADDED, padding_length)

      payload = frame.payload_to_bytes
      payload.size.should eq(1 + data.size + padding_length)
      payload[0].should eq(padding_length)
      payload[1, data.size].should eq(data)
    end
  end
end
