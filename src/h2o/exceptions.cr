module H2O
  class Error < Exception; end

  class ConnectionError < Error
    getter error_code : ErrorCode

    def initialize(message : String, @error_code : ErrorCode = ErrorCode::InternalError)
      super(message)
    end
  end

  class FrameError < Error; end

  class ProtocolError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::ProtocolError)
    end
  end

  class CompressionError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::CompressionError)
    end
  end

  class FlowControlError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::FlowControlError)
    end
  end

  class StreamError < Error
    getter stream_id : StreamId
    getter error_code : ErrorCode

    def initialize(message : String, @stream_id : StreamId, @error_code : ErrorCode = ErrorCode::InternalError)
      super(message)
    end
  end

  # Additional error types for specific protocol violations
  class FrameSizeError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::FrameSizeError)
    end
  end

  class ContinuationFloodError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::EnhanceYourCalm)
    end
  end

  class RapidResetAttackError < ConnectionError
    def initialize(message : String)
      super(message, ErrorCode::EnhanceYourCalm)
    end
  end
end
