require "./stream_refactored"

module H2O
  # Refactored StreamPool class following SRP principles
  # Manages the collection of streams without object pooling
  class StreamPool
    property streams : StreamsHash
    property next_stream_id : StreamId
    property max_concurrent_streams : UInt32?
    property rate_limit_config : StreamRateLimitConfig
    property initial_window_size : Int32
    @cached_active_streams : StreamArray?
    @cached_closed_streams : StreamArray?
    @cache_valid : Bool
    @stream_creation_times : Array(Time)
    @stream_reset_times : Array(Time)
    @stream_lifecycle_events : Array(StreamLifecycleEvent)
    @stream_state_metrics : Hash(StreamState, Int32)

    def initialize(@max_concurrent_streams : UInt32? = nil,
                   @rate_limit_config : StreamRateLimitConfig = StreamRateLimitConfig.new,
                   @initial_window_size : Int32 = 65535)
      @streams = StreamsHash.new
      @next_stream_id = 1_u32
      @cached_active_streams = nil
      @cached_closed_streams = nil
      @cache_valid = false
      @stream_creation_times = Array(Time).new
      @stream_reset_times = Array(Time).new
      @stream_lifecycle_events = Array(StreamLifecycleEvent).new
      @stream_state_metrics = Hash(StreamState, Int32).new
    end

    # Stream lifecycle management
    def create_stream : Stream
      validate_can_create_stream
      validate_stream_rate_limit

      stream_id = allocate_stream_id
      # Always create new stream - no object pooling for memory safety
      stream = Stream.new(stream_id, @initial_window_size)
      @streams[stream_id] = stream
      invalidate_cache

      # Track stream creation for rate limiting and metrics
      current_time = Time.utc
      @stream_creation_times << current_time
      @stream_lifecycle_events << StreamLifecycleEvent.new(stream_id, StreamEventType::Created, current_time)
      update_state_metrics(StreamState::Idle, 1)
      cleanup_old_tracking_data

      stream
    end

    def get_stream(id : StreamId) : Stream?
      @streams[id]?
    end

    def remove_stream(id : StreamId) : Nil
      stream = @streams[id]?
      if stream
        current_time = Time.utc
        @stream_lifecycle_events << StreamLifecycleEvent.new(id, StreamEventType::Closed, current_time)

        # Update state metrics
        update_state_metrics(stream.state, -1)

        # No object pooling - let stream be garbage collected
      end
      @streams.delete(id)
      invalidate_cache
    end

    def active_streams : StreamArray
      if @cache_valid && (cached = @cached_active_streams)
        return cached
      end

      refresh_cache
      @cached_active_streams.as(StreamArray)
    end

    def closed_streams : StreamArray
      if @cache_valid && (cached = @cached_closed_streams)
        return cached
      end

      refresh_cache
      @cached_closed_streams.as(StreamArray)
    end

    def cleanup_closed_streams : Nil
      streams_to_remove = closed_streams.dup
      streams_to_remove.each do |stream|
        @streams.delete(stream.id)
      end
      invalidate_cache
    end

    def stream_count : Int32
      active_streams.size
    end

    # Stream priority management
    def prioritized_streams : Array(Stream)
      active_streams.sort!
    end

    def streams_by_priority : Array(Stream)
      prioritized_streams
    end

    # Flow control management
    def streams_needing_window_update : Array(Stream)
      active_streams.select(&.needs_window_update?)
    end

    def streams_ready_for_data : Array(Stream)
      active_streams.select(&.flow_control_available?)
    end

    def update_all_stream_window_sizes(new_size : Int32) : Nil
      active_streams.each do |stream|
        stream.update_initial_window_size(new_size)
      end
    end

    # Rate limiting and attack protection
    def track_stream_reset(stream_id : StreamId) : Nil
      # Validate rate limit before tracking
      current_resets = get_recent_reset_count(@rate_limit_config.reset_detection_window)
      if current_resets >= @rate_limit_config.max_resets_per_minute
        raise RapidResetAttackError.new("Stream reset rate limit exceeded: #{current_resets}/min")
      end

      current_time = Time.utc
      @stream_reset_times << current_time
      @stream_lifecycle_events << StreamLifecycleEvent.new(stream_id, StreamEventType::Reset, current_time)
      cleanup_old_tracking_data
    end

    def get_recent_reset_count(window : Time::Span = 1.minute) : UInt32
      cutoff_time = Time.utc - window
      @stream_reset_times.count { |reset_time| reset_time > cutoff_time }.to_u32
    end

    def get_recent_creation_count(window : Time::Span = 1.second) : UInt32
      cutoff_time = Time.utc - window
      @stream_creation_times.count { |creation_time| creation_time > cutoff_time }.to_u32
    end

    def detect_rapid_reset_attack : Array(StreamId)
      rapid_reset_streams = Array(StreamId).new
      active_streams.each do |stream|
        if stream.rapid_reset?
          rapid_reset_streams << stream.id
        end
      end
      rapid_reset_streams
    end

    # Stream state metrics
    def state_metrics : Hash(StreamState, Int32)
      @stream_state_metrics.dup
    end

    def total_streams_created : UInt32
      @stream_creation_times.size.to_u32
    end

    def total_streams_reset : UInt32
      @stream_reset_times.size.to_u32
    end

    # Stream filtering and querying
    def streams_in_state(state : StreamState) : Array(Stream)
      active_streams.select { |stream| stream.state == state }
    end

    def streams_with_priority(weight : UInt8) : Array(Stream)
      active_streams.select { |stream| stream.priority_weight == weight }
    end

    def streams_depending_on(dependency : StreamId) : Array(Stream)
      active_streams.select(&.prioritizer.depends_on?(dependency))
    end

    # Pool statistics
    def statistics : Hash(Symbol, Int32 | UInt32 | Float64)
      total_active = active_streams.size
      total_closed = closed_streams.size
      total_streams = total_active + total_closed

      {
        :total_streams           => total_streams,
        :active_streams          => total_active,
        :closed_streams          => total_closed,
        :streams_created         => total_streams_created,
        :streams_reset           => total_streams_reset,
        :rapid_reset_rate        => calculate_rapid_reset_rate,
        :average_stream_lifetime => calculate_average_stream_lifetime,
        :max_concurrent_streams  => @max_concurrent_streams || 0_u32,
        :current_utilization     => calculate_utilization_rate,
      }
    end

    private def invalidate_cache : Nil
      @cache_valid = false
      @cached_active_streams = nil
      @cached_closed_streams = nil
    end

    private def refresh_cache : Nil
      active = StreamArray.new
      closed = StreamArray.new

      @streams.each_value do |stream|
        if stream.closed?
          closed << stream
        else
          active << stream
        end
      end

      @cached_active_streams = active
      @cached_closed_streams = closed
      @cache_valid = true
    end

    private def validate_can_create_stream : Nil
      if max_streams = @max_concurrent_streams
        if stream_count >= max_streams
          raise ConnectionError.new("Maximum concurrent streams reached: #{max_streams}", ErrorCode::ProtocolError)
        end
      end
    end

    private def validate_stream_rate_limit : Nil
      current_creations = get_recent_creation_count(@rate_limit_config.rate_limit_window)
      if current_creations >= @rate_limit_config.max_streams_per_second
        raise RapidResetAttackError.new("Stream creation rate limit exceeded: #{current_creations}/s")
      end
    end

    private def cleanup_old_tracking_data : Nil
      cutoff_time = Time.utc - 5.minutes

      @stream_creation_times.reject! { |time| time < cutoff_time }
      @stream_reset_times.reject! { |time| time < cutoff_time }
      @stream_lifecycle_events.reject! { |event| event.timestamp < cutoff_time }
    end

    private def allocate_stream_id : StreamId
      current_id = @next_stream_id
      @next_stream_id += 2
      current_id
    end

    private def update_state_metrics(state : StreamState, delta : Int32) : Nil
      current_count = @stream_state_metrics[state]? || 0
      @stream_state_metrics[state] = current_count + delta
    end

    private def calculate_rapid_reset_rate : Float64
      total_resets = total_streams_reset
      return 0.0 if total_resets == 0

      rapid_resets = closed_streams.count(&.rapid_reset?)
      rapid_resets.to_f64 / total_resets.to_f64
    end

    private def calculate_average_stream_lifetime : Float64
      closed_stream_array = closed_streams
      return 0.0 if closed_stream_array.empty?

      total_lifetime = closed_stream_array.sum(&.lifetime.total_milliseconds)
      total_lifetime / closed_stream_array.size
    end

    private def calculate_utilization_rate : Float64
      return 0.0 unless max_streams = @max_concurrent_streams
      stream_count.to_f64 / max_streams.to_f64
    end
  end
end
