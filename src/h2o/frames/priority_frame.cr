module H2O
  class PriorityFrame < Frame
    property exclusive : Bool
    property dependency : StreamId
    property weight : UInt8

    def initialize(stream_id : StreamId, exclusive : Bool, dependency : StreamId, weight : UInt8)
      raise FrameError.new("PRIORITY frame must have non-zero stream ID") if stream_id == 0

      @exclusive = exclusive
      @dependency = dependency & 0x7fffffff_u32
      @weight = weight

      super(5_u32, FrameType::Priority, 0_u8, stream_id)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : PriorityFrame
      raise FrameError.new("PRIORITY frame must have non-zero stream ID") if stream_id == 0
      raise FrameError.new("PRIORITY frame must have 5-byte payload") if payload.size != 5

      dependency_data = ((payload[0].to_u32 << 24) | (payload[1].to_u32 << 16) |
                         (payload[2].to_u32 << 8) | payload[3].to_u32)
      exclusive = (dependency_data & 0x80000000_u32) != 0
      dependency = dependency_data & 0x7fffffff_u32
      weight = payload[4]

      frame = new(stream_id, exclusive, dependency, weight)
      frame.set_length(length)
      frame.set_flags(flags)
      frame
    end

    def payload_to_bytes : Bytes
      result = Bytes.new(5)

      dependency_value = @dependency
      dependency_value |= 0x80000000_u32 if @exclusive

      result[0] = ((dependency_value >> 24) & 0xff).to_u8
      result[1] = ((dependency_value >> 16) & 0xff).to_u8
      result[2] = ((dependency_value >> 8) & 0xff).to_u8
      result[3] = (dependency_value & 0xff).to_u8
      result[4] = @weight

      result
    end
  end
end
