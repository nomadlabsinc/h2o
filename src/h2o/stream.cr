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

    def initialize(@id : StreamId, @local_window_size : Int32 = 65535, @remote_window_size : Int32 = 65535)
      @state = StreamState::Idle
      @request = nil
      @response = nil
      @headers_complete = false
      @data_complete = false
      @incoming_data = IO::Memory.new
      @response_channel = ResponseChannel.new(1)
    end

    def send_headers(headers_frame : HeadersFrame) : Nil
      validate_can_send_headers
      transition_on_send_headers(headers_frame.end_stream?)
    end

    def send_data(data_frame : DataFrame) : Nil
      validate_can_send_data
      validate_flow_control(data_frame.data.size)
      @remote_window_size -= data_frame.data.size
      transition_on_send_data(data_frame.end_stream?)
    end

    def receive_headers(headers_frame : HeadersFrame, decoded_headers : Headers? = nil) : Nil
      validate_can_receive_headers

      # Create response if it doesn't exist
      if @response.nil?
        @response = Response.new(0)
      end

      # Process decoded headers if provided
      if decoded_headers && (response = @response)
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
      validate_can_receive_data

      @incoming_data.write(data_frame.data)
      @local_window_size -= data_frame.data.size

      transition_on_receive_data(data_frame.end_stream?)

      if @data_complete && @headers_complete
        finalize_response
      end
    end

    def receive_rst_stream(rst_frame : RstStreamFrame) : Nil
      @state = StreamState::Closed
      @response_channel.send(nil)
    end

    def receive_window_update(window_frame : WindowUpdateFrame) : Nil
      @remote_window_size += window_frame.window_size_increment.to_i32
    end

    def await_response : Response?
      Timeout(Response?).execute(5.seconds) do
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
      @local_window_size += increment
      WindowUpdateFrame.new(@id, increment.to_u32)
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

    private def validate_flow_control(data_size : Int32) : Nil
      if data_size > @remote_window_size
        raise FlowControlError.new("Data size exceeds available window: #{data_size} > #{@remote_window_size}")
      end
    end

    private def transition_on_send_headers(end_stream : Bool) : Nil
      case @state
      when .idle?
        @state = end_stream ? StreamState::HalfClosedLocal : StreamState::Open
      when .open?
        @state = StreamState::HalfClosedLocal if end_stream
      end
    end

    private def transition_on_send_data(end_stream : Bool) : Nil
      if end_stream
        case @state
        when .open?
          @state = StreamState::HalfClosedLocal
        when .half_closed_remote?
          @state = StreamState::Closed
        end
      end
    end

    private def transition_on_receive_headers(end_stream : Bool) : Nil
      case @state
      when .idle?
        @state = end_stream ? StreamState::HalfClosedRemote : StreamState::Open
      when .open?
        @state = StreamState::HalfClosedRemote if end_stream
      when .half_closed_local?
        @state = StreamState::Closed if end_stream
      end
    end

    private def transition_on_receive_data(end_stream : Bool) : Nil
      @data_complete = true if end_stream

      if end_stream
        case @state
        when .open?
          @state = StreamState::HalfClosedRemote
        when .half_closed_local?
          @state = StreamState::Closed
        end
      end
    end

    private def finalize_response : Nil
      if response = @response
        response.body = @incoming_data.to_s
        @response_channel.send(response)
      end
    end
  end

  class StreamPool
    property streams : StreamsHash
    property next_stream_id : StreamId
    property max_concurrent_streams : UInt32?
    @cached_active_streams : StreamArray?
    @cached_closed_streams : StreamArray?
    @cache_valid : Bool

    def initialize(@max_concurrent_streams : UInt32? = nil)
      @streams = StreamsHash.new
      @next_stream_id = 1_u32
      @cached_active_streams = nil
      @cached_closed_streams = nil
      @cache_valid = false
    end

    def create_stream : Stream
      validate_can_create_stream

      stream_id = allocate_stream_id
      stream = Stream.new(stream_id)
      @streams[stream_id] = stream
      invalidate_cache

      stream
    end

    def get_stream(id : StreamId) : Stream?
      @streams[id]?
    end

    def remove_stream(id : StreamId) : Nil
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

    private def allocate_stream_id : StreamId
      current_id = @next_stream_id
      @next_stream_id += 2
      current_id
    end
  end
end
