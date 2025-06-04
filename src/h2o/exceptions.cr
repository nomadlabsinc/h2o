module H2O
  class Error < Exception; end

  class ConnectionError < Error; end

  class FrameError < Error; end

  class ProtocolError < Error; end

  class CompressionError < Error; end

  class FlowControlError < Error; end

  class StreamError < Error
    getter stream_id : StreamId

    def initialize(message : String, @stream_id : StreamId)
      super(message)
    end
  end

  class TimeoutError < Error; end
end
