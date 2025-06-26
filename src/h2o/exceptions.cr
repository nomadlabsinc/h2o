module H2O
  class Error < Exception; end

  class ConnectionError < Error; end

  class FrameError < Error; end

  class ProtocolError < Error; end

  class CompressionError < Error; end

  class FlowControlError < Error; end

  class StreamError < Error
    getter stream_id : UInt32

    def initialize(message : String, @stream_id : UInt32)
      super(message)
    end
  end
end
