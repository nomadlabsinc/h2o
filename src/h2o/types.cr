module H2O
  # Type aliases for improved readability
  alias ConnectionsHash = Hash(String, BaseConnection)
  alias FiberRef = Fiber?
  alias Headers = Hash(String, String)
  alias StreamsHash = Hash(UInt32, Stream)
  alias StreamArray = Array(Stream)
  alias TimeoutCallback = Proc(Bool)
  alias StreamResetTracker = Hash(Time, UInt32)
  alias ResponseChannel = Channel(Response?)
  alias ContinuationFrameBuffer = IO::Memory
  alias HeaderFragmentState = NamedTuple(
    stream_id: UInt32,
    accumulated_size: Int32,
    continuation_count: Int32,
    buffer: IO::Memory)

  # Circuit breaker related aliases for performance and readability
  alias CircuitBreakerResult = Response
  alias ConnectionResult = BaseConnection?
  alias ProtocolResult = ProtocolVersion?
  alias RequestBlock = Proc(Response)
  alias UrlParseResult = {URI, String}

  # Client method parameter aliases
  alias CircuitBreakerOptions = NamedTuple(
    bypass_circuit_breaker: Bool,
    circuit_breaker: Bool?)

  # Connection management aliases
  alias HostPort = {String, Int32}

  # Common test and benchmark aliases
  alias TestResult = {String, Bool, Time::Span}
  alias TestResultChannel = Channel(TestResult)
  alias TestResultArray = Array(TestResult)
  alias ResponseArray = Array(Response?)
  alias BoolChannel = Channel(Bool)
  alias BoolArray = Array(Bool)
  alias TimeArray = Array(Time::Span)
  alias StringArray = Array(String)
  alias BytesArray = Array(Bytes)

  # Performance measurement aliases
  alias MonotonicTime = Time::Span # Time.monotonic returns Time::Span
  alias ProcessStatus = Process::Status

  # Channel timeout patterns
  alias ChannelTimeout = Time::Span

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

  # Custom exception for rapid reset attack detection
  class RapidResetAttackError < Exception
    def initialize(message : String = "Rapid reset attack detected")
      super(message)
    end
  end

  # Custom exceptions for CONTINUATION flood attack detection
  class ContinuationFloodError < Exception
    def initialize(message : String = "CONTINUATION flood attack detected")
      super(message)
    end
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
    property error : String?

    def initialize(@status : Int32, @headers : Headers = Headers.new, @body : String = "", @protocol : String = "HTTP/2", @error : String? = nil)
    end

    # Create an error response for failed requests
    def self.error(status : Int32, message : String, protocol : String = "HTTP/2") : Response
      Response.new(
        status: status,
        headers: Headers.new,
        body: "",
        protocol: protocol,
        error: message
      )
    end

    # Check if this response represents an error
    def error? : Bool
      !@error.nil?
    end

    # Check if this response represents a successful request
    def success? : Bool
      @error.nil? && @status >= 200 && @status < 400
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

  # HPACK security configuration and errors
  class HpackBombError < Exception
    def initialize(message : String = "HPACK bomb attack detected")
      super(message)
    end
  end

  struct HpackSecurityLimits
    property max_decompressed_size : Int32
    property max_header_count : Int32
    property max_string_length : Int32
    property max_dynamic_table_size : Int32
    property compression_ratio_limit : Float64

    def initialize(@max_decompressed_size : Int32 = 65536,
                   @max_header_count : Int32 = 100,
                   @max_string_length : Int32 = 8192,
                   @max_dynamic_table_size : Int32 = 65536,
                   @compression_ratio_limit : Float64 = 10.0)
    end
  end

  # Stream lifecycle tracking for CVE-2023-44487 mitigation
  struct StreamLifecycleEvent
    property stream_id : StreamId
    property event_type : StreamEventType
    property timestamp : Time

    def initialize(@stream_id : StreamId, @event_type : StreamEventType, @timestamp : Time = Time.utc)
    end
  end

  enum StreamEventType
    Created
    Reset
    Closed
  end

  # Rate limiting configuration for stream creation
  struct StreamRateLimitConfig
    property max_streams_per_second : UInt32
    property max_resets_per_minute : UInt32
    property reset_detection_window : Time::Span
    property rate_limit_window : Time::Span

    def initialize(@max_streams_per_second : UInt32 = 100_u32,
                   @max_resets_per_minute : UInt32 = 1000_u32,
                   @reset_detection_window : Time::Span = 1.minute,
                   @rate_limit_window : Time::Span = 1.second)
    end
  end

  # Configuration for CONTINUATION frame flood protection
  struct ContinuationLimits
    property max_continuation_frames : Int32
    property max_header_size : Int32
    property max_accumulated_size : Int32

    def initialize(@max_continuation_frames : Int32 = 10,
                   @max_header_size : Int32 = 8192,
                   @max_accumulated_size : Int32 = 16384)
    end
  end
end
