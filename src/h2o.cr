require "log"
require "openssl"
require "socket"
require "uri"

require "./h2o/version"
require "./h2o/exceptions"
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

  alias Headers = Hash(String, String)
  alias StreamId = UInt32
end
