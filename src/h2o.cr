require "log"
require "openssl"
require "socket"
require "uri"

require "./h2o/version"
require "./h2o/exceptions"
require "./h2o/timeout"
require "./h2o/types"
require "./h2o/buffer_pool"
require "./h2o/object_pool"
require "./h2o/string_pool"
require "./h2o/circuit_breaker"
require "./h2o/tls_cache"
require "./h2o/cert_validator"
require "./h2o/io_optimizer"
require "./h2o/simd_optimizer"
require "./h2o/protocol_optimizer"
require "./h2o/tls"
require "./h2o/preface"
require "./h2o/frames/frame"
require "./h2o/frames/data_frame"
require "./h2o/frames/headers_frame"
require "./h2o/frames/settings_frame"
require "./h2o/frames/ping_frame"
require "./h2o/frames/goaway_frame"
require "./h2o/frames/window_update_frame"
require "./h2o/frames/rst_stream_frame"
require "./h2o/frames/priority_frame"
require "./h2o/frames/continuation_frame"
require "./h2o/frames/push_promise_frame"
require "./h2o/frames/frame_batch_processor"
require "./h2o/hpack/static_table"
require "./h2o/hpack/dynamic_table"
require "./h2o/hpack/huffman"
require "./h2o/hpack/encoder"
require "./h2o/hpack/decoder"
require "./h2o/hpack/presets"
require "./h2o/stream"
require "./h2o/http1_connection"
require "./h2o/h1/client"
require "./h2o/h2/client"
# require "./h2o/h2/optimized_client"  # Temporarily disabled due to compilation issues
require "./h2o/client"

module H2O
  Log = ::Log.for("h2o")

  # Additional type aliases (core ones are in types.cr)
  alias FrameBytes = Bytes
  alias FramePayload = Bytes
  alias SettingsHash = Hash(SettingIdentifier, UInt32)

  # Additional collection types
  alias H1ConnectionsHash = Hash(String, H1::Client)
  alias H2ConnectionsHash = Hash(String, H2::Client)
  alias HeaderTable = Array(HPACK::StaticEntry)
  alias HeaderEntry = Tuple(String, String)
  alias IntegerValue = Int32

  # Additional channel types
  alias FrameChannel = Channel(Frame)

  # IO and buffer types
  alias IOBuffer = IO::Memory
  alias ByteBuffer = Bytes
  alias SliceData = Slice(UInt8)

  # Global configuration for H2O
  class Configuration
    property circuit_breaker_enabled : Bool = false
    property default_circuit_breaker : Breaker?
    property default_failure_threshold : Int32 = 5
    property default_recovery_timeout : Time::Span = 60.seconds
    property default_timeout : Time::Span = 5.seconds

    def initialize
    end
  end

  @@config = Configuration.new

  def self.configure(&block : Configuration -> Nil) : Nil
    block.call(@@config)
  end

  def self.config : Configuration
    @@config
  end
end
