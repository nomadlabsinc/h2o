require "../spec_helper"

describe "H2O max_frame_size handling" do
  describe "Settings frame max_frame_size" do
    it "correctly stores max_frame_size setting" do
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::MaxFrameSize] = 32768_u32

      frame = H2O::SettingsFrame.new(settings)
      frame.settings[H2O::SettingIdentifier::MaxFrameSize].should eq(32768_u32)

      bytes = frame.to_bytes
      bytes.should_not be_nil
      bytes.size.should be > 0
    end

    it "validates max_frame_size within HTTP/2 limits" do
      # Test minimum allowed value (2^14 = 16384)
      settings = Hash(H2O::SettingIdentifier, UInt32).new
      settings[H2O::SettingIdentifier::MaxFrameSize] = 16384_u32

      frame = H2O::SettingsFrame.new(settings)
      frame.settings[H2O::SettingIdentifier::MaxFrameSize].should eq(16384_u32)

      # Test maximum allowed value (2^24 - 1 = 16777215)
      settings[H2O::SettingIdentifier::MaxFrameSize] = 16777215_u32
      frame = H2O::SettingsFrame.new(settings)
      frame.settings[H2O::SettingIdentifier::MaxFrameSize].should eq(16777215_u32)
    end
  end

  describe "DataFrame size validation" do
    it "creates data frame when size is within max_frame_size" do
      data = Bytes.new(8192) # 8KB data
      stream_id = 1_u32

      frame = H2O::DataFrame.new(stream_id, data)
      frame.data.size.should eq(8192)
      frame.stream_id.should eq(stream_id)
    end

    it "validates data frame size against HTTP/2 maximum" do
      # Test with maximum allowed frame size
      max_data_size = 16777215 - 1 # Account for potential padding overhead
      data = Bytes.new(max_data_size)
      stream_id = 1_u32

      frame = H2O::DataFrame.new(stream_id, data)
      frame.data.size.should eq(max_data_size)
    end

    it "handles empty data frames correctly" do
      empty_data = Bytes.empty
      stream_id = 1_u32

      frame = H2O::DataFrame.new(stream_id, empty_data)
      frame.data.size.should eq(0)
      frame.stream_id.should eq(stream_id)
    end
  end

  describe "HeadersFrame size validation" do
    it "creates headers frame when size is within max_frame_size" do
      header_block = Bytes.new(8192) # 8KB headers
      stream_id = 1_u32

      frame = H2O::HeadersFrame.new(stream_id, header_block)
      frame.header_block.size.should eq(8192)
      frame.stream_id.should eq(stream_id)
    end

    it "handles empty header blocks correctly" do
      empty_headers = Bytes.empty
      stream_id = 1_u32

      frame = H2O::HeadersFrame.new(stream_id, empty_headers)
      frame.header_block.size.should eq(0)
      frame.stream_id.should eq(stream_id)
    end
  end

  describe "ContinuationFrame for header fragmentation" do
    it "creates continuation frame for header fragmentation" do
      header_fragment = Bytes.new(4096) # 4KB fragment
      stream_id = 1_u32

      frame = H2O::ContinuationFrame.new(stream_id, header_fragment, false)
      frame.header_block.size.should eq(4096)
      frame.stream_id.should eq(stream_id)
      frame.end_headers?.should eq(false)
    end

    it "marks final continuation frame with end_headers flag" do
      header_fragment = Bytes.new(2048) # 2KB fragment
      stream_id = 1_u32

      frame = H2O::ContinuationFrame.new(stream_id, header_fragment, true)
      frame.header_block.size.should eq(2048)
      frame.stream_id.should eq(stream_id)
      frame.end_headers?.should eq(true)
    end
  end

  describe "Settings struct default values" do
    it "initializes with correct default max_frame_size" do
      settings = H2O::Settings.new
      settings.max_frame_size.should eq(16384_u32) # HTTP/2 spec minimum
    end

    it "allows updating max_frame_size" do
      settings = H2O::Settings.new
      settings.max_frame_size = 32768_u32
      settings.max_frame_size.should eq(32768_u32)
    end
  end
end
