module H2O
  # Protocol-level optimizations for HTTP/2
  module ProtocolOptimizer
    # Frame coalescing settings
    COALESCE_THRESHOLD = 3 # Min frames to trigger coalescing
    COALESCE_WINDOW    = 5.milliseconds
    MAX_COALESCED_SIZE = 16_384 # 16KB max coalesced payload

    # Window update batching
    WINDOW_UPDATE_THRESHOLD = 8_192 # 8KB threshold for updates
    WINDOW_UPDATE_RATIO     =   0.5 # Update when 50% consumed

    # Priority optimization
    DEFAULT_STREAM_WEIGHT = 16_u8
    HIGH_PRIORITY_WEIGHT  = 32_u8
    LOW_PRIORITY_WEIGHT   =  8_u8

    # Frame coalescing for better network utilization
    class FrameCoalescer
      property frames : Array(Frame)
      property mutex : Mutex
      property total_size : Int32

      def initialize
        @frames = Array(Frame).new
        @total_size = 0
        @mutex = Mutex.new
      end

      # Add frame for potential coalescing
      def add(frame : Frame) : Bool
        @mutex.synchronize do
          # Don't coalesce certain frame types
          return false if frame.is_a?(SettingsFrame) || frame.is_a?(PingFrame)

          # Check size limits
          frame_size = 9 + frame.length # Header + payload
          return false if @total_size + frame_size > MAX_COALESCED_SIZE

          @frames << frame
          @total_size += frame_size
          true
        end
      end

      # Get coalesced frames if beneficial
      def get_coalesced : Array(Frame)?
        @mutex.synchronize do
          return nil if @frames.size < COALESCE_THRESHOLD

          # Group frames by stream for better cache locality
          grouped = @frames.group_by(&.stream_id)

          # Return frames ordered by stream ID for better processing
          result = grouped.flat_map { |_, frames| frames }
          # Create new array instead of clearing to avoid reuse
          @frames = Array(Frame).new
          @total_size = 0
          result
        end
      end

      def clear : Nil
        @mutex.synchronize do
          # Create new array instead of clearing to avoid reuse
          @frames = Array(Frame).new
          @total_size = 0
        end
      end
    end

    # Optimized window update management
    class WindowUpdateOptimizer
      property connection_consumed : Int32
      property connection_window : Int32
      property last_update_time : Time
      property mutex : Mutex
      property stream_consumed : Hash(StreamId, Int32)
      property stream_windows : Hash(StreamId, Int32)

      def initialize(@connection_window : Int32 = 65535)
        @connection_consumed = 0
        @stream_consumed = Hash(StreamId, Int32).new(0)
        @stream_windows = Hash(StreamId, Int32).new(65535)
        @last_update_time = Time.utc
        @mutex = Mutex.new
      end

      # Track consumed bytes
      def consume(stream_id : StreamId, bytes : Int32) : Nil
        @mutex.synchronize do
          @connection_consumed += bytes
          @stream_consumed[stream_id] = @stream_consumed[stream_id] + bytes
        end
      end

      # Check if window update is needed
      def needs_update?(stream_id : StreamId) : Bool
        @mutex.synchronize do
          stream_consumed = @stream_consumed[stream_id]
          stream_window = @stream_windows[stream_id]

          # Update if consumed more than threshold
          stream_consumed >= WINDOW_UPDATE_THRESHOLD ||
            stream_consumed.to_f / stream_window >= WINDOW_UPDATE_RATIO
        end
      end

      # Get optimized window updates
      def get_updates : Array(WindowUpdate)
        @mutex.synchronize do
          updates = Array(WindowUpdate).new

          # Check connection-level update
          if @connection_consumed >= WINDOW_UPDATE_THRESHOLD
            updates << WindowUpdate.new(0_u32, @connection_consumed)
            @connection_consumed = 0
          end

          # Check stream-level updates
          @stream_consumed.each do |stream_id, consumed|
            if consumed >= WINDOW_UPDATE_THRESHOLD
              updates << WindowUpdate.new(stream_id, consumed)
              @stream_consumed[stream_id] = 0
            end
          end

          @last_update_time = Time.utc
          updates
        end
      end

      struct WindowUpdate
        property increment : UInt32
        property stream_id : StreamId

        def initialize(@stream_id : StreamId, consumed : Int32)
          @increment = consumed.to_u32
        end
      end
    end

    # Stream priority optimizer
    class PriorityOptimizer
      property dependencies : Hash(StreamId, StreamId)
      property weights : Hash(StreamId, UInt8)

      def initialize
        @dependencies = Hash(StreamId, StreamId).new
        @weights = Hash(StreamId, UInt8).new(DEFAULT_STREAM_WEIGHT)
      end

      # Set stream priority based on content type
      def optimize_by_content_type(stream_id : StreamId, content_type : String?) : Nil
        return unless content_type

        weight = case content_type
                 when /^text\/html/
                   HIGH_PRIORITY_WEIGHT # HTML gets high priority
                 when /^application\/json/
                   HIGH_PRIORITY_WEIGHT # API responses high priority
                 when /^text\/css/, /^application\/javascript/
                   DEFAULT_STREAM_WEIGHT # CSS/JS medium priority
                 when /^image\//
                   LOW_PRIORITY_WEIGHT # Images low priority
                 else
                   DEFAULT_STREAM_WEIGHT
                 end

        @weights[stream_id] = weight
      end

      # Get optimized write order for frames
      def get_write_order(streams : Array(StreamId)) : Array(StreamId)
        # Sort by weight (higher weight = higher priority)
        streams.sort_by { |id| 256 - @weights[id] }
      end
    end

    # Protocol state optimizer
    class StateOptimizer
      # Cache for protocol state decisions
      property state_cache : Hash(String, Bool)
      property mutex : Mutex

      def initialize
        @state_cache = Hash(String, Bool).new
        @mutex = Mutex.new
      end

      # Cache HTTP/2 support per host
      def cache_http2_support(host : String, supported : Bool) : Nil
        @mutex.synchronize do
          @state_cache["h2:#{host}"] = supported
        end
      end

      # Check cached HTTP/2 support
      def http2_supported?(host : String) : Bool?
        @mutex.synchronize do
          @state_cache["h2:#{host}"]?
        end
      end

      # Cache ALPN negotiation results
      def cache_alpn_protocol(host : String, protocol : String) : Nil
        @mutex.synchronize do
          @state_cache["alpn:#{host}"] = (protocol == "h2")
        end
      end

      # Get cached ALPN result
      def cached_alpn_protocol(host : String) : String?
        @mutex.synchronize do
          supported = @state_cache["alpn:#{host}"]?
          supported.nil? ? nil : (supported ? "h2" : "http/1.1")
        end
      end
    end

    # Settings optimizer for better defaults
    module SettingsOptimizer
      # Optimized settings for different scenarios
      def self.high_throughput_settings : Hash(SettingIdentifier, UInt32)
        {
          SettingIdentifier::InitialWindowSize    => 1_048_576_u32,  # 1MB window
          SettingIdentifier::MaxConcurrentStreams => 1000_u32,       # High concurrency
          SettingIdentifier::MaxFrameSize         => 16_777_215_u32, # Max allowed
          SettingIdentifier::MaxHeaderListSize    => 65_536_u32,     # 64KB headers
          SettingIdentifier::EnablePush           => 0_u32,          # Disable push
        }
      end

      def self.low_latency_settings : Hash(SettingIdentifier, UInt32)
        {
          SettingIdentifier::InitialWindowSize    => 65_535_u32, # Default window
          SettingIdentifier::MaxConcurrentStreams => 100_u32,    # Moderate concurrency
          SettingIdentifier::MaxFrameSize         => 16_384_u32, # Smaller frames
          SettingIdentifier::MaxHeaderListSize    => 16_384_u32, # Smaller headers
          SettingIdentifier::EnablePush           => 0_u32,      # Disable push
        }
      end

      def self.balanced_settings : Hash(SettingIdentifier, UInt32)
        {
          SettingIdentifier::InitialWindowSize    => 262_144_u32, # 256KB window
          SettingIdentifier::MaxConcurrentStreams => 250_u32,     # Balanced concurrency
          SettingIdentifier::MaxFrameSize         => 32_768_u32,  # 32KB frames
          SettingIdentifier::MaxHeaderListSize    => 32_768_u32,  # 32KB headers
          SettingIdentifier::EnablePush           => 0_u32,       # Disable push
        }
      end
    end
  end
end
