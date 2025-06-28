module H2O
  # Frame type for handling unknown frame types as per RFC 7540 Section 4.1
  # Unknown frame types must be ignored by implementations
  class UnknownFrame < Frame
    property payload : Bytes

    def initialize(length : UInt32, frame_type : FrameType, flags : UInt8, stream_id : StreamId, payload : Bytes)
      super(length, frame_type, flags, stream_id)
      @payload = payload
    end

    def payload_to_bytes : Bytes
      @payload
    end
  end
end
