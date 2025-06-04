require "../../spec_helper"

describe H2O::SettingsFrame do
  describe "#new" do
    it "creates an empty settings frame" do
      frame = H2O::SettingsFrame.new
      frame.length.should eq(0)
      frame.frame_type.should eq(H2O::FrameType::Settings)
      frame.stream_id.should eq(0)
      frame.settings.empty?.should be_true
    end

    it "creates a settings ACK frame" do
      frame = H2O::SettingsFrame.new(ack: true)
      frame.ack?.should be_true
      frame.length.should eq(0)
    end

    it "creates a settings frame with settings" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::MaxFrameSize] = 32768_u32

      frame = H2O::SettingsFrame.new(settings)
      frame.settings.size.should eq(1)
      frame.settings[H2O::SettingIdentifier::MaxFrameSize].should eq(32768_u32)
      frame.length.should eq(6)
    end
  end

  describe "#to_bytes" do
    it "serializes empty settings frame correctly" do
      frame = H2O::SettingsFrame.new
      bytes = frame.to_bytes

      bytes.size.should eq(9)
      bytes[0].should eq(0) # length high byte
      bytes[1].should eq(0) # length middle byte
      bytes[2].should eq(0) # length low byte
      bytes[3].should eq(4) # frame type (SETTINGS)
      bytes[4].should eq(0) # flags
    end
  end
end

describe H2O::PingFrame do
  describe "#new" do
    it "creates a ping frame with default data" do
      frame = H2O::PingFrame.new
      frame.length.should eq(8)
      frame.frame_type.should eq(H2O::FrameType::Ping)
      frame.stream_id.should eq(0)
      frame.opaque_data.size.should eq(8)
    end

    it "creates a ping ACK frame" do
      data = Bytes.new(8, 0x42_u8)
      frame = H2O::PingFrame.new(data, ack: true)
      frame.ack?.should be_true
      frame.opaque_data.should eq(data)
    end
  end

  describe "#create_ack" do
    it "creates an ACK frame with same data" do
      original_data = Bytes.new(8, 0x55_u8)
      ping = H2O::PingFrame.new(original_data)
      ack = ping.create_ack

      ack.ack?.should be_true
      ack.opaque_data.should eq(original_data)
    end
  end
end
