require "log"
require "openssl"
require "socket"
require "uri"

require "./h2o/version"
require "./h2o/exceptions"
require "./h2o/timeout"
require "./h2o/types"
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
require "./h2o/hpack/static_table"
require "./h2o/hpack/dynamic_table"
require "./h2o/hpack/huffman"
require "./h2o/hpack/encoder"
require "./h2o/hpack/decoder"
require "./h2o/stream"
require "./h2o/connection"
require "./h2o/client"

module H2O
  Log = ::Log.for("h2o")

  # Core HTTP/2 type aliases
  alias Headers = Hash(String, String)
  alias StreamId = UInt32

  # Frame and protocol types
  alias FrameBytes = Bytes
  alias FramePayload = Bytes
  alias SettingsHash = Hash(SettingIdentifier, UInt32)

  # Collection types
  alias StreamsHash = Hash(StreamId, Stream)
  alias ConnectionsHash = Hash(String, Connection)
  # HPACK type aliases
  alias HeaderTable = Array(HPACK::StaticEntry)
  alias HeaderEntry = Tuple(String, String)
  alias IntegerValue = Int32
  alias StreamArray = Array(Stream)

  # Channel types
  alias ResponseChannel = Channel(Response?)
  alias FrameChannel = Channel(Frame)
  alias OutgoingFrameChannel = Channel(Frame)
  alias IncomingFrameChannel = Channel(Frame)

  # Fiber and callback types
  alias FiberRef = Fiber?
  alias TimeoutCallback = Proc(Bool)
  alias TimeoutResult = Bool

  # IO and buffer types
  alias IOBuffer = IO::Memory
  alias ByteBuffer = Bytes
  alias SliceData = Slice(UInt8)
end
