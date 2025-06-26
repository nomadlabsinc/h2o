module H2O
  class SettingsFrame < Frame
    FLAG_ACK = 0x1_u8

    property settings : SettingsHash

    def initialize(settings : SettingsHash = SettingsHash.new, ack : Bool = false)
      @settings = settings
      flags = ack ? FLAG_ACK : 0_u8
      length = ack ? 0_u32 : (settings.size * 6).to_u32

      super(length, FrameType::Settings, flags, 0_u32)
      validate_ack_frame if ack
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : UInt32, payload : Bytes) : SettingsFrame
      raise FrameError.new("SETTINGS frame must have stream ID 0") if stream_id != 0

      if flags & FLAG_ACK != 0
        raise FrameError.new("SETTINGS ACK frame must have empty payload") unless payload.empty?
        return new(ack: true)
      end

      raise FrameError.new("SETTINGS frame payload length must be multiple of 6") if payload.size % 6 != 0

      settings = Hash(SettingIdentifier, UInt32).new
      (0...payload.size).step(6) do |i|
        identifier = SettingIdentifier.new(((payload[i].to_u16 << 8) | payload[i + 1].to_u16))
        value = ((payload[i + 2].to_u32 << 24) | (payload[i + 3].to_u32 << 16) |
                 (payload[i + 4].to_u32 << 8) | payload[i + 5].to_u32)
        settings[identifier] = value
      end

      frame = new(settings)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      return Bytes.empty if ack?

      result = Bytes.new(@settings.size * 6)
      offset = 0

      @settings.each do |identifier, value|
        id = identifier.value
        result[offset] = ((id >> 8) & 0xff).to_u8
        result[offset + 1] = (id & 0xFF).to_u8
        result[offset + 2] = ((value >> 24) & 0xFF).to_u8
        result[offset + 3] = ((value >> 16) & 0xFF).to_u8
        result[offset + 4] = ((value >> 8) & 0xFF).to_u8
        result[offset + 5] = (value & 0xFF).to_u8
        offset += 6
      end

      result
    end

    def ack? : Bool
      (@flags & FLAG_ACK) != 0
    end

    def [](identifier : SettingIdentifier) : UInt32?
      @settings[identifier]?
    end

    def []=(identifier : SettingIdentifier, value : UInt32) : UInt32
      @settings[identifier] = value
    end

    def reset_for_reuse : Nil
      @flags = 0_u8
      @length = 0_u32
      @settings.clear
      @stream_id = 0_u32
    end

    private def validate_ack_frame : Nil
      raise FrameError.new("SETTINGS ACK frame must have empty payload") unless @settings.empty?
    end
  end
end
