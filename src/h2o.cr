require "log"
require "openssl"
require "socket"
require "uri"

require "./h2o/version"
require "./h2o/exceptions"
require "./h2o/timeout"
require "./h2o/types"
require "./h2o/buffer_pool_stats"
require "./h2o/buffer_pool"
require "./h2o/object_pool" # Re-enabled with fiber-safe implementation
require "./h2o/string_pool"
require "./h2o/circuit_breaker"
require "./h2o/tls_cache"
require "./h2o/cert_validator"
require "./h2o/io_optimizer"
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
require "./h2o/frames/unknown_frame"
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
require "./h2o/h2/optimized_client"
require "./h2o/client"
require "./h2o/http_client"
require "./h2o/connection_pool"
require "./h2o/protocol_negotiator"
require "./h2o/circuit_breaker_manager"
require "./h2o/error_handling"
require "./h2o/request_translator"
require "./h2o/response_translator"

module H2O
  Log = ::Log.for("h2o")

  # Constants for environment variable parsing
  TRUTHY_ENV_VALUES = {"true", "yes", "1", "on"}

  # Helper for checking if an environment variable is set to a truthy value
  # Accepts: true, yes, 1, on for consistency with existing codebase
  def self.env_flag_enabled?(env_var : String) : Bool
    TRUTHY_ENV_VALUES.includes?(ENV.fetch(env_var, "false").downcase)
  end

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
    property default_timeout : Time::Span = 1.seconds
    property verify_ssl : Bool = true

    def initialize
      # Check environment variable for SSL verification override
      if ENV["H2O_VERIFY_SSL"]?
        @verify_ssl = H2O.env_flag_enabled?("H2O_VERIFY_SSL")
      end
    end
  end

  @@config = Configuration.new
  @@config_mutex = Mutex.new

  def self.configure(&block : Configuration -> Nil) : Nil
    @@config_mutex.synchronize do
      block.call(@@config)
    end
  end

  def self.config : Configuration
    # Config reads don't need mutex since Configuration properties are simple values
    # and Crystal ensures memory visibility across fibers
    @@config
  end
end
