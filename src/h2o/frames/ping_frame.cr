module H2O
  class PingFrame < Frame
    FLAG_ACK          = 0x1_u8
    PING_PAYLOAD_SIZE =   8_u8

    property opaque_data : Bytes

    def initialize(opaque_data : Bytes = Bytes.new(PING_PAYLOAD_SIZE), ack : Bool = false)
      raise FrameError.new("PING frame payload must be 8 bytes") if opaque_data.size != PING_PAYLOAD_SIZE

      @opaque_data = opaque_data
      flags = ack ? FLAG_ACK : 0_u8

      super(PING_PAYLOAD_SIZE.to_u32, FrameType::Ping, flags, 0_u32)
    end

    def self.from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, payload : Bytes) : PingFrame
      raise FrameError.new("PING frame must have stream ID 0") if stream_id != 0
      raise FrameError.new("PING frame must have 8-byte payload") if payload.size != PING_PAYLOAD_SIZE

      ack = (flags & FLAG_ACK) != 0
      frame = allocate
      frame.initialize_from_payload(length, flags, stream_id, payload)
      frame
    end

    def payload_to_bytes : Bytes
      @opaque_data
    end

    def ack? : Bool
      (@flags & FLAG_ACK) != 0
    end

    def create_ack : PingFrame
      PingFrame.new(@opaque_data, ack: true)
    end

    protected def initialize_from_payload(length : UInt32, flags : UInt8, stream_id : StreamId, opaque_data : Bytes)
      @length = length
      @frame_type = FrameType::Ping
      @flags = flags
      @stream_id = stream_id
      @opaque_data = opaque_data
    end
  end
end
