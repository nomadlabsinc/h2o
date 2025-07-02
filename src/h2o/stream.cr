require "./flow_control_validation"
require "./header_list_validation"

module H2O
  class Stream
    property id : StreamId
    property state : StreamState
    property request : Request?
    property response : Response?
    property headers_complete : Bool
    property data_complete : Bool
    property local_window_size : Int32
    property remote_window_size : Int32
    property incoming_data : IO::Memory
    property response_channel : ResponseChannel
    property created_at : Time
    property last_activity : Time
    property closed_at : Time?
    property priority : UInt8
    property dependency : StreamId?

    # State transition optimization lookup table
    VALID_TRANSITIONS = {
      StreamState::Idle             => [StreamState::Open, StreamState::HalfClosedLocal, StreamState::HalfClosedRemote, StreamState::Closed],
      StreamState::Open             => [StreamState::HalfClosedLocal, StreamState::HalfClosedRemote, StreamState::Closed],
      StreamState::HalfClosedLocal  => [StreamState::Closed],
      StreamState::HalfClosedRemote => [StreamState::Closed],
      StreamState::Closed           => [] of StreamState,
    }

    def initialize(@id : StreamId, @local_window_size : Int32 = 65535, @remote_window_size : Int32 = 65535)
      @state = StreamState::Idle
      @request = nil
      @response = nil
      @headers_complete = false
      @data_complete = false
      @incoming_data = IO::Memory.new
      @response_channel = ResponseChannel.new(0)
      @created_at = Time.utc
      @last_activity = Time.utc
      @closed_at = nil
      @priority = 16_u8 # Default priority
      @dependency = nil
    end

    # DISABLED: Reset stream for object pool reuse - causes memory corruption
    # def reset_for_reuse(new_id : StreamId) : Nil
    #   @id = new_id
    #   @state = StreamState::Idle
    #   @request = nil
    #   @response = nil
    #   @headers_complete = false
    #   @data_complete = false
    #   @incoming_data = IO::Memory.new
    #   @response_channel = ResponseChannel.new(0)
    #   @created_at = Time.utc
    #   @last_activity = Time.utc
    #   @closed_at = nil
    #   @local_window_size = 65535
    #   @remote_window_size = 65535
    #   @priority = 16_u8
    #   @dependency = nil
    # end

    # DISABLED: Check if stream can be returned to object pool - causes memory corruption
    # def can_be_pooled? : Bool
    #   closed? && @incoming_data.size < 1024 # Only pool small streams
    # end

    def send_headers(headers_frame : HeadersFrame) : Nil
      validate_can_send_headers
      transition_on_send_headers(headers_frame.end_stream?)
    end

    def send_data(data_frame : DataFrame) : Nil
      validate_can_send_data

      # Strict flow control validation
      data_size = data_frame.data.size
      if data_size > 0 # Empty DATA frames don't consume flow control
        FlowControlValidation.validate_data_frame_flow_control(data_size, @remote_window_size, @id)
        @remote_window_size -= data_size
      end

      # Validate flow control state after update
      FlowControlValidation.validate_flow_control_state(@local_window_size, @remote_window_size, @id)

      transition_on_send_data(data_frame.end_stream?)
    end

    def receive_headers(headers_frame : HeadersFrame, decoded_headers : Headers? = nil) : Nil
      # Strict state validation following Rust h2 and Go net/http2 patterns
      case @state
      when .idle?
        # Valid - transition to open/half-closed based on end_stream flag
      when .open?
        # Valid - can receive headers in open state
      when .half_closed_local?
        # Valid - can receive response headers when we've sent all our data
      when .half_closed_remote?
        # Invalid - remote has already closed their side
        raise StreamError.new("Cannot receive HEADERS in state #{@state}", @id, ErrorCode::StreamClosed)
      when .closed?
        # Invalid - stream is completely closed
        raise StreamError.new("Cannot receive HEADERS in state #{@state}", @id, ErrorCode::StreamClosed)
      else
        raise StreamError.new("Invalid state #{@state} for receiving HEADERS", @id, ErrorCode::ProtocolError)
      end

      @last_activity = Time.utc

      # Create response if it doesn't exist
      if @response.nil?
        @response = Response.new(0)
      end

      # Process decoded headers if provided
      if decoded_headers && (response = @response)
        # Comprehensive header list validation for HTTP/2 responses
        HeaderListValidation.validate_http2_header_list(decoded_headers, false) # false = response

        # Set status from :status pseudo-header
        if status = decoded_headers[":status"]?
          response.status = status.to_i32
        end

        # Add regular headers (excluding pseudo-headers)
        decoded_headers.each do |name, value|
          unless name.starts_with?(":")
            response.headers[name] = value
          end
        end
      end

      @headers_complete = headers_frame.end_headers?
      if headers_frame.end_stream?
        @data_complete = true
      end

      transition_on_receive_headers(headers_frame.end_stream?)

      # Check if response is complete (headers only, no data)
      if @data_complete && @headers_complete
        finalize_response
      end
    end

    def receive_data(data_frame : DataFrame) : Nil
      # Strict state validation following Rust h2 and Go net/http2 patterns
      unless can_receive_data?
        case @state
        when .half_closed_remote?, .closed?
          raise StreamError.new("Cannot receive DATA in state #{@state}", @id, ErrorCode::StreamClosed)
        when .idle?
          raise ConnectionError.new("DATA frame on idle stream #{@id}", ErrorCode::ProtocolError)
        else
          raise StreamError.new("Invalid state #{@state} for receiving DATA", @id, ErrorCode::ProtocolError)
        end
      end

      # Strict flow control validation for received data
      data_size = data_frame.data.size
      if data_size > 0 # Empty DATA frames don't consume flow control
        FlowControlValidation.validate_data_frame_flow_control(data_size, @local_window_size, @id)
        @local_window_size -= data_size
      end

      @last_activity = Time.utc
      @incoming_data.write(data_frame.data)

      # Validate flow control state after consuming data
      FlowControlValidation.validate_flow_control_state(@local_window_size, @remote_window_size, @id)

      transition_on_receive_data(data_frame.end_stream?)

      if @data_complete && @headers_complete
        finalize_response
      end
    end

    def receive_rst_stream(rst_frame : RstStreamFrame) : Nil
      @state = StreamState::Closed
      @last_activity = Time.utc
      @closed_at = Time.utc
      @response_channel.send(nil)
    end

    def receive_window_update(window_frame : WindowUpdateFrame) : Nil
      increment = window_frame.window_size_increment

      # Strict WINDOW_UPDATE validation
      FlowControlValidation.validate_window_update_increment(increment)
      FlowControlValidation.validate_window_size_after_update(@remote_window_size, increment, @id)

      @remote_window_size += increment.to_i32

      # Validate final flow control state
      FlowControlValidation.validate_flow_control_state(@local_window_size, @remote_window_size, @id)
    end

    def await_response(timeout : Time::Span = 5.seconds) : Response?
      Timeout(Response?).execute(timeout) do
        @response_channel.receive
      end
    rescue Channel::ClosedError
      nil
    end

    def closed? : Bool
      @state == StreamState::Closed
    end

    def can_send_data? : Bool
      @state == StreamState::Open || @state == StreamState::HalfClosedRemote
    end

    def can_receive_data? : Bool
      @state == StreamState::Open || @state == StreamState::HalfClosedLocal
    end

    def flow_control_available? : Bool
      @remote_window_size > 0
    end

    def needs_window_update? : Bool
      @local_window_size <= 32767
    end

    def create_window_update(increment : Int32) : WindowUpdateFrame
      # Validate increment before creating frame
      increment_u32 = increment.to_u32
      FlowControlValidation.validate_window_update_increment(increment_u32)
      FlowControlValidation.validate_window_size_after_update(@local_window_size, increment_u32, @id)

      @local_window_size += increment

      # Validate final state
      FlowControlValidation.validate_flow_control_state(@local_window_size, @remote_window_size, @id)

      WindowUpdateFrame.new(@id, increment_u32)
    end

    def rapid_reset? : Bool
      return false unless closed_at = @closed_at
      (closed_at - @created_at) < 100.milliseconds
    end

    def lifetime : Time::Span
      end_time = @closed_at || Time.utc
      end_time - @created_at
    end

    private def validate_can_send_headers : Nil
      case @state
      when .idle?
      when .open?
      else
        raise StreamError.new("Cannot send HEADERS in state #{@state}", @id)
      end
    end

    private def validate_can_send_data : Nil
      unless can_send_data?
        raise StreamError.new("Cannot send DATA in state #{@state}", @id)
      end
    end

    private def validate_can_receive_headers : Nil
      case @state
      when .idle?
      when .open?
      when .half_closed_local?
      else
        raise StreamError.new("Cannot receive HEADERS in state #{@state}", @id)
      end
    end

    private def validate_can_receive_data : Nil
      unless can_receive_data?
        raise StreamError.new("Cannot receive DATA in state #{@state}", @id)
      end
    end

    # Optimized state transition with validation
    private def transition_state(new_state : StreamState) : Nil
      valid_transitions = VALID_TRANSITIONS[@state]?
      unless valid_transitions && valid_transitions.includes?(new_state)
        raise StreamError.new("Invalid state transition from #{@state} to #{new_state}", @id)
      end

      @state = new_state
      @closed_at = Time.utc if new_state == StreamState::Closed
    end

    private def transition_on_send_headers(end_stream : Bool) : Nil
      case @state
      when .idle?
        transition_state(end_stream ? StreamState::HalfClosedLocal : StreamState::Open)
      when .open?
        transition_state(StreamState::HalfClosedLocal) if end_stream
      end
    end

    private def transition_on_send_data(end_stream : Bool) : Nil
      return unless end_stream

      case @state
      when .open?
        transition_state(StreamState::HalfClosedLocal)
      when .half_closed_remote?
        transition_state(StreamState::Closed)
      end
    end

    private def transition_on_receive_headers(end_stream : Bool) : Nil
      case @state
      when .idle?
        transition_state(end_stream ? StreamState::HalfClosedRemote : StreamState::Open)
      when .open?
        transition_state(StreamState::HalfClosedRemote) if end_stream
      when .half_closed_local?
        transition_state(StreamState::Closed) if end_stream
      end
    end

    private def transition_on_receive_data(end_stream : Bool) : Nil
      @data_complete = true if end_stream
      return unless end_stream

      case @state
      when .open?
        transition_state(StreamState::HalfClosedRemote)
      when .half_closed_local?
        transition_state(StreamState::Closed)
      end
    end

    # Stream priority management for HTTP/2 prioritization
    def set_priority(priority : UInt8, dependency : StreamId? = nil) : Nil
      @priority = priority
      @dependency = dependency
    end

    def priority_weight : UInt8
      @priority
    end

    private def finalize_response : Nil
      if response = @response
        # Use to_slice for binary data or to_s for text data - let Response handle it
        response.body = @incoming_data.to_s
        @response_channel.send(response)

        # Clear the memory buffer to free up resources
        @incoming_data = IO::Memory.new
      end
    end
  end

  # Stream object pool for efficient stream creation and reuse
  class StreamObjectPool
    DEFAULT_POOL_SIZE = 50

    # Pooling is disabled - these are no longer used
    @@pool_size = Atomic(Int32).new(0)

    def self.get_stream(id : StreamId) : Stream
      # Disabled pooling to avoid memory issues
      Stream.new(id)
    end

    def self.return_stream(stream : Stream) : Nil
      # Disabled pooling to avoid memory issues
      # Let stream be garbage collected
    end

    def self.pool_stats : {size: Int32, capacity: Int32}
      {size: @@pool_size.get, capacity: DEFAULT_POOL_SIZE}
    end
  end

  class StreamPool
    property streams : StreamsHash
    property next_stream_id : StreamId
    property max_concurrent_streams : UInt32?
    property rate_limit_config : StreamRateLimitConfig
    @cached_active_streams : StreamArray?
    @cached_closed_streams : StreamArray?
    @cache_valid : Bool
    @stream_creation_times : Array(Time)
    @stream_reset_times : Array(Time)
    @stream_lifecycle_events : Array(StreamLifecycleEvent)
    @stream_state_metrics : Hash(StreamState, Int32)

    def initialize(@max_concurrent_streams : UInt32? = nil, @rate_limit_config : StreamRateLimitConfig = StreamRateLimitConfig.new)
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

    def create_stream : Stream
      validate_can_create_stream
      validate_stream_rate_limit

      stream_id = allocate_stream_id
      # DISABLED: Object pool causes memory corruption - create new stream directly
      stream = Stream.new(stream_id)
      @streams[stream_id] = stream
      invalidate_cache

      # Track stream creation for rate limiting and metrics
      current_time = Time.utc
      @stream_creation_times << current_time
      @stream_lifecycle_events << StreamLifecycleEvent.new(stream_id, StreamEventType::Created, current_time)
      @stream_state_metrics[StreamState::Idle] = (@stream_state_metrics[StreamState::Idle]? || 0) + 1
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
        @stream_state_metrics[stream.state] = (@stream_state_metrics[stream.state]? || 1) - 1

        # DISABLED: Object pool causes memory corruption - let stream be garbage collected
        # StreamObjectPool.return_stream(stream)
      end
      @streams.delete(id)
      invalidate_cache
    end

    def active_streams : StreamArray
      if @cache_valid && (cached = @cached_active_streams)
        return cached
      end

      refresh_cache
      # refresh_cache guarantees that @cached_active_streams is set
      @cached_active_streams.as(StreamArray)
    end

    def closed_streams : StreamArray
      if @cache_valid && (cached = @cached_closed_streams)
        return cached
      end

      refresh_cache
      # refresh_cache guarantees that @cached_closed_streams is set
      @cached_closed_streams.as(StreamArray)
    end

    def cleanup_closed_streams : Nil
      # Get closed streams before deletion to avoid cache invalidation during iteration
      streams_to_remove : StreamArray = closed_streams
      streams_to_remove.each do |stream|
        @streams.delete(stream.id)
      end
      invalidate_cache
    end

    def stream_count : Int32
      active_streams.size
    end

    # Stream priority queue for HTTP/2 prioritization
    def prioritized_streams : Array(Stream)
      streams = active_streams
      streams.sort! do |stream_a, stream_b|
        # Lower priority value = higher priority (inverse sort)
        if stream_a.priority_weight != stream_b.priority_weight
          stream_a.priority_weight <=> stream_b.priority_weight
        else
          # If same priority, use stream ID as tiebreaker
          stream_a.id <=> stream_b.id
        end
      end
    end

    # Stream state metrics for monitoring
    def state_metrics : Hash(StreamState, Int32)
      @stream_state_metrics.dup
    end

    # Efficient flow control management
    def streams_needing_window_update : Array(Stream)
      active_streams.select(&.needs_window_update?)
    end

    # Get streams ready for data transmission
    def streams_ready_for_data : Array(Stream)
      active_streams.select(&.flow_control_available?)
    end

    private def invalidate_cache : Nil
      @cache_valid = false
      @cached_active_streams = nil
      @cached_closed_streams = nil
    end

    private def refresh_cache : Nil
      active : StreamArray = StreamArray.new
      closed : StreamArray = StreamArray.new

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
          raise ConnectionError.new("Maximum concurrent streams reached: #{max_streams}")
        end
      end
    end

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
  end
end
