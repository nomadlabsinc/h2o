require "../../spec_helper"

describe H2O::SettingsFrame do
  describe "#payload_to_bytes" do
    it "handles normal settings values within UInt8 range" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::HeaderTableSize] = 255_u32

      frame = H2O::SettingsFrame.new(settings)
      bytes = frame.payload_to_bytes

      bytes.size.should eq(6)
    end

    it "correctly handles settings values that exceed UInt8 range" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::HeaderTableSize] = 4096_u32

      frame = H2O::SettingsFrame.new(settings)
      bytes = frame.payload_to_bytes

      bytes.size.should eq(6)

      # Verify the value is correctly encoded as 32-bit
      value = (bytes[2].to_u32 << 24) | (bytes[3].to_u32 << 16) | (bytes[4].to_u32 << 8) | bytes[5].to_u32
      value.should eq(4096_u32)
    end

    it "handles multiple settings with large values correctly" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::HeaderTableSize] = 4096_u32
      settings[H2O::SettingIdentifier::InitialWindowSize] = 65535_u32
      settings[H2O::SettingIdentifier::MaxFrameSize] = 16384_u32

      frame = H2O::SettingsFrame.new(settings)
      bytes = frame.payload_to_bytes

      bytes.size.should eq(18) # 3 settings * 6 bytes each
    end

    it "correctly serializes settings values using 32-bit encoding" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::HeaderTableSize] = 4096_u32

      frame = H2O::SettingsFrame.new(settings)
      bytes = frame.payload_to_bytes

      # Should have 6 bytes: 2 for identifier, 4 for value
      bytes.size.should eq(6)

      # Verify identifier (HeaderTableSize = 0x1)
      identifier = (bytes[0].to_u16 << 8) | bytes[1].to_u16
      identifier.should eq(1_u16)

      # Verify value (4096)
      value = (bytes[2].to_u32 << 24) | (bytes[3].to_u32 << 16) | (bytes[4].to_u32 << 8) | bytes[5].to_u32
      value.should eq(4096_u32)
    end
  end

  describe "integration test reproducing bug from issue #11" do
    it "creates initial settings frame without overflow" do
      # This reproduces the exact scenario from the bug report
      initial_settings = H2O::Preface.create_initial_settings

      # This should not raise an overflow error
      bytes = initial_settings.payload_to_bytes

      # Verify the frame was created correctly
      bytes.size.should eq(36) # 6 settings * 6 bytes each
    end
  end
end
