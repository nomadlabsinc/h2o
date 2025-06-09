require "../../spec_helper"

module H2O
  describe "Frame reuse methods" do
    describe DataFrame do
      it "resets frame for reuse" do
        data = "Hello, World!".to_slice
        frame = DataFrame.new(1_u32, data, DataFrame::FLAG_END_STREAM, 5_u8)

        frame.data.should eq data
        frame.flags.should eq DataFrame::FLAG_END_STREAM
        frame.padding_length.should eq 5_u8
        frame.stream_id.should eq 1_u32

        frame.reset_for_reuse

        frame.data.should eq Bytes.empty
        frame.flags.should eq 0_u8
        frame.padding_length.should eq 0_u8
        frame.stream_id.should eq 0_u32
        frame.length.should eq 0_u32
      end

      it "updates data and recalculates length" do
        frame = DataFrame.new(1_u32, Bytes.empty)
        frame.length.should eq 0_u32

        new_data = "New data content".to_slice
        frame.set_data(new_data)

        frame.data.should eq new_data
        frame.length.should eq new_data.size
      end

      it "recalculates length with padding" do
        frame = DataFrame.new(1_u32, Bytes.empty, DataFrame::FLAG_PADDED, 10_u8)
        frame.length.should eq 11_u32 # 0 data + 1 padding length byte + 10 padding

        new_data = "Test".to_slice
        frame.set_data(new_data)

        frame.data.should eq new_data
        frame.length.should eq 15_u32 # 4 data + 1 padding length byte + 10 padding
      end
    end

    describe HeadersFrame do
      it "resets frame for reuse" do
        header_block = "header:value".to_slice
        frame = HeadersFrame.new(
          stream_id: 1_u32,
          header_block: header_block,
          flags: HeadersFrame::FLAG_END_HEADERS | HeadersFrame::FLAG_PRIORITY,
          padding_length: 5_u8,
          priority_exclusive: true,
          priority_dependency: 3_u32,
          priority_weight: 255_u8
        )

        frame.header_block.should eq header_block
        frame.flags.should eq(HeadersFrame::FLAG_END_HEADERS | HeadersFrame::FLAG_PRIORITY)
        frame.padding_length.should eq 5_u8
        frame.priority_exclusive.should be_true
        frame.priority_dependency.should eq 3_u32
        frame.priority_weight.should eq 255_u8
        frame.stream_id.should eq 1_u32

        frame.reset_for_reuse

        frame.header_block.should eq Bytes.empty
        frame.flags.should eq 0_u8
        frame.padding_length.should eq 0_u8
        frame.priority_exclusive.should be_false
        frame.priority_dependency.should eq 0_u32
        frame.priority_weight.should eq 0_u8
        frame.stream_id.should eq 0_u32
        frame.length.should eq 0_u32
      end

      it "updates header block and recalculates length" do
        frame = HeadersFrame.new(1_u32, Bytes.empty)
        frame.length.should eq 0_u32

        new_header = "new:header".to_slice
        frame.set_header_block(new_header)

        frame.header_block.should eq new_header
        frame.length.should eq new_header.size
      end

      it "recalculates length with padding and priority" do
        frame = HeadersFrame.new(
          stream_id: 1_u32,
          header_block: Bytes.empty,
          flags: HeadersFrame::FLAG_PADDED | HeadersFrame::FLAG_PRIORITY,
          padding_length: 10_u8
        )
        frame.length.should eq 16_u32 # 0 header + 1 padding byte + 5 priority + 10 padding

        new_header = "test:value".to_slice
        frame.set_header_block(new_header)

        frame.header_block.should eq new_header
        frame.length.should eq 26_u32 # 10 header + 1 padding byte + 5 priority + 10 padding
      end
    end

    describe SettingsFrame do
      it "resets frame for reuse" do
        settings = SettingsHash{
          SettingIdentifier::HeaderTableSize      => 4096_u32,
          SettingIdentifier::EnablePush           => 1_u32,
          SettingIdentifier::MaxConcurrentStreams => 100_u32,
        }
        frame = SettingsFrame.new(settings)

        frame.settings.should eq settings
        frame.flags.should eq 0_u8
        frame.stream_id.should eq 0_u32
        frame.length.should eq 18_u32 # 3 settings * 6 bytes each

        frame.reset_for_reuse

        frame.settings.should be_empty
        frame.flags.should eq 0_u8
        frame.stream_id.should eq 0_u32
        frame.length.should eq 0_u32
      end

      it "resets ACK frame for reuse" do
        frame = SettingsFrame.new(ack: true)

        frame.ack?.should be_true
        frame.settings.should be_empty
        frame.flags.should eq SettingsFrame::FLAG_ACK
        frame.stream_id.should eq 0_u32
        frame.length.should eq 0_u32

        frame.reset_for_reuse

        frame.settings.should be_empty
        frame.flags.should eq 0_u8
        frame.ack?.should be_false
        frame.stream_id.should eq 0_u32
        frame.length.should eq 0_u32
      end
    end

    describe WindowUpdateFrame do
      it "resets frame for reuse" do
        frame = WindowUpdateFrame.new(1_u32, 65535_u32)

        frame.window_size_increment.should eq 65535_u32
        frame.stream_id.should eq 1_u32
        frame.flags.should eq 0_u8
        frame.length.should eq 4_u32

        frame.reset_for_reuse

        frame.window_size_increment.should eq 0_u32
        frame.stream_id.should eq 0_u32
        frame.flags.should eq 0_u8
        frame.length.should eq 0_u32
      end
    end
  end
end
