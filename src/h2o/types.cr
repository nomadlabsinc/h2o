module H2O
  # Type aliases for improved readability
  alias ConnectionsHash = Hash(String, BaseConnection)
  alias FiberRef = Fiber?
  alias Headers = Hash(String, String)
  alias IncomingFrameChannel = Channel(Frame)
  alias OutgoingFrameChannel = Channel(Frame)
  alias StreamId = UInt32
  alias StreamsHash = Hash(StreamId, Stream)
  alias TimeoutCallback = Proc(Bool)
  alias TimeoutResult = Bool

  enum FrameType : UInt8
    Data         = 0x0
    Headers      = 0x1
    Priority     = 0x2
    RstStream    = 0x3
    Settings     = 0x4
    PushPromise  = 0x5
    Ping         = 0x6
    Goaway       = 0x7
    WindowUpdate = 0x8
    Continuation = 0x9
  end

  enum StreamState
    Idle
    Open
    HalfClosedLocal
    HalfClosedRemote
    Closed
  end

  enum ErrorCode : UInt32
    NoError            = 0x0
    ProtocolError      = 0x1
    InternalError      = 0x2
    FlowControlError   = 0x3
    SettingsTimeout    = 0x4
    StreamClosed       = 0x5
    FrameSizeError     = 0x6
    RefusedStream      = 0x7
    Cancel             = 0x8
    CompressionError   = 0x9
    ConnectError       = 0xa
    EnhanceYourCalm    = 0xb
    InadequateSecurity = 0xc
    Http11Required     = 0xd
  end

  enum SettingIdentifier : UInt16
    HeaderTableSize      = 0x1
    EnablePush           = 0x2
    MaxConcurrentStreams = 0x3
    InitialWindowSize    = 0x4
    MaxFrameSize         = 0x5
    MaxHeaderListSize    = 0x6
  end

  struct Settings
    property header_table_size : UInt32
    property enable_push : Bool
    property max_concurrent_streams : UInt32?
    property initial_window_size : UInt32
    property max_frame_size : UInt32
    property max_header_list_size : UInt32?

    def initialize
      @header_table_size = 4096_u32
      @enable_push = true
      @max_concurrent_streams = nil
      @initial_window_size = 65535_u32
      @max_frame_size = 16384_u32
      @max_header_list_size = nil
    end
  end

  struct Request
    property method : String
    property path : String
    property headers : Headers
    property body : String?

    def initialize(@method : String, @path : String, @headers : Headers = Headers.new, @body : String? = nil)
    end
  end

  class Response
    property status : Int32
    property headers : Headers
    property body : String
    property protocol : String

    def initialize(@status : Int32, @headers : Headers = Headers.new, @body : String = "", @protocol : String = "HTTP/2")
    end
  end

  enum ProtocolVersion
    Http11
    Http2
  end

  class ProtocolCache
    CACHE_TTL = 1.hour

    def initialize
      @cache = Hash(String, ProtocolCacheEntry).new
    end

    def get_preferred_protocol(host : String, port : Int32) : ProtocolVersion?
      key = "#{host}:#{port}"
      entry = @cache[key]?

      return nil unless entry
      return nil if entry.expired?

      entry.protocol
    end

    def cache_protocol(host : String, port : Int32, protocol : ProtocolVersion) : Nil
      key = "#{host}:#{port}"
      @cache[key] = ProtocolCacheEntry.new(protocol, Time.utc + CACHE_TTL)
    end

    def cleanup_expired : Nil
      @cache.reject! { |_, entry| entry.expired? }
    end
  end

  private struct ProtocolCacheEntry
    property protocol : ProtocolVersion
    property expires_at : Time

    def initialize(@protocol : ProtocolVersion, @expires_at : Time)
    end

    def expired? : Bool
      Time.utc > @expires_at
    end
  end
end
