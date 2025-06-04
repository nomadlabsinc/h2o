module H2O
  module Preface
    CONNECTION_PREFACE        = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".to_slice
    CONNECTION_PREFACE_LENGTH = 24

    def self.send_preface(io : IO) : Nil
      io.write(CONNECTION_PREFACE)
      io.flush
    end

    def self.verify_preface(io : IO) : Bool
      received = Bytes.new(CONNECTION_PREFACE_LENGTH)
      bytes_read = io.read_fully(received)
      received == CONNECTION_PREFACE
    rescue IO::Error
      false
    end

    def self.create_initial_settings : SettingsFrame
      settings = Hash(SettingIdentifier, UInt32).new
      settings[SettingIdentifier::HeaderTableSize] = 4096_u32
      settings[SettingIdentifier::EnablePush] = 0_u32
      settings[SettingIdentifier::MaxConcurrentStreams] = 100_u32
      settings[SettingIdentifier::InitialWindowSize] = 65535_u32
      settings[SettingIdentifier::MaxFrameSize] = 16384_u32
      settings[SettingIdentifier::MaxHeaderListSize] = 8192_u32

      SettingsFrame.new(settings)
    end

    def self.create_settings_ack : SettingsFrame
      SettingsFrame.new(ack: true)
    end
  end
end
