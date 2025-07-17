require "./stream/flow_control"
require "./stream/prioritizer"
require "./header_list_validation"

module H2O
  # Refactored Stream class following SRP principles
  # Focuses on stream state management while delegating flow control and priority concerns
  class Stream
    property id : StreamId
    property state : StreamState
    property request : Request?
    property response : Response?
    property headers_complete : Bool
    property data_complete : Bool
    property incoming_data : IO::Memory
    property response_channel : ResponseChannel
    property created_at : Time
    property last_activity : Time
    property closed_at : Time?
    property flow_control : Stream::FlowControl
    property prioritizer : Stream::Prioritizer

    # State transition optimization lookup table
    VALID_TRANSITIONS = {
      StreamState::Idle             => [StreamState::Open, StreamState::HalfClosedLocal, StreamState::HalfClosedRemote, StreamState::Closed],
      StreamState::Open             => [StreamState::HalfClosedLocal, StreamState::HalfClosedRemote, StreamState::Closed],
      StreamState::HalfClosedLocal  => [StreamState::Closed],
      StreamState::HalfClosedRemote => [StreamState::Closed],
      StreamState::Closed           => [] of StreamState,
    }

    def initialize(@id : StreamId, initial_window_size : Int32 = 65535)
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
      @flow_control = Stream::FlowControl.new(initial_window_size)
      @prioritizer = Stream::Prioritizer.new
    end

    # Stream lifecycle methods
    def send_headers(headers_frame : HeadersFrame) : Nil
      validate_can_send_headers
      transition_on_send_headers(headers_frame.end_stream?)
    end

    def send_data(data_frame : DataFrame) : Nil
      validate_can_send_data

      # Use flow control module for data sending
      data_size = data_frame.data.size
      @flow_control.consume_remote_window(data_size, @id)

      transition_on_send_data(data_frame.end_stream?)
    end

    def receive_headers(headers_frame : HeadersFrame, decoded_headers : Headers? = nil) : Nil
      validate_can_receive_headers
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
      validate_can_receive_data

      # Use flow control module for data receiving
      data_size = data_frame.data.size
      @flow_control.consume_local_window(data_size, @id)

      @last_activity = Time.utc
      @incoming_data.write(data_frame.data)

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
      @flow_control.update_remote_window(window_frame.window_size_increment, @id)
    end

    def receive_priority(priority_frame : PriorityFrame) : Nil
      @prioritizer.update_from_priority_frame(priority_frame, @id)
    end

    # Stream state queries
    def closed? : Bool
      @state == StreamState::Closed
    end

    def can_send_data? : Bool
      @state == StreamState::Open || @state == StreamState::HalfClosedRemote
    end

    def can_receive_data? : Bool
      @state == StreamState::Open || @state == StreamState::HalfClosedLocal
    end

    # Flow control delegation
    def flow_control_available? : Bool
      @flow_control.flow_control_available?
    end

    def needs_window_update? : Bool
      @flow_control.needs_window_update?
    end

    def create_window_update(increment : Int32) : WindowUpdateFrame
      @flow_control.create_window_update(increment, @id)
    end

    def update_initial_window_size(new_size : Int32) : Int32
      @flow_control.update_initial_window_size(new_size, @id)
    end

    # Priority delegation
    def set_priority(weight : UInt8, dependency : StreamId? = nil, exclusive : Bool = false) : Nil
      @prioritizer.set_priority(weight, dependency, exclusive)
    end

    def priority_weight : UInt8
      @prioritizer.weight
    end

    def priority_value : Int32
      @prioritizer.priority_value
    end

    def create_priority_frame : PriorityFrame
      @prioritizer.create_priority_frame(@id)
    end

    # Stream lifecycle queries
    def await_response(timeout : Time::Span = 5.seconds) : Response?
      Timeout(Response?).execute(timeout) do
        @response_channel.receive
      end
    rescue Channel::ClosedError
      nil
    end

    def rapid_reset? : Bool
      return false unless closed_at = @closed_at
      (closed_at - @created_at) < 100.milliseconds
    end

    def lifetime : Time::Span
      end_time = @closed_at || Time.utc
      end_time - @created_at
    end

    # Stream comparison for priority sorting
    def <=>(other : Stream) : Int32
      # Primary sort: priority value
      comparison = @prioritizer <=> other.prioritizer
      return comparison unless comparison == 0

      # Secondary sort: stream ID (for deterministic ordering)
      @id <=> other.id
    end

    # Stream statistics
    def statistics : Hash(Symbol, Int32 | UInt8 | Float64 | Bool | Nil)
      flow_stats = @flow_control.statistics
      priority_stats = @prioritizer.to_hash

      {
        :stream_id           => @id,
        :state               => @state.to_i32,
        :lifetime_ms         => lifetime.total_milliseconds.to_i32,
        :rapid_reset         => rapid_reset?,
        :local_window        => flow_stats[:local_window],
        :remote_window       => flow_stats[:remote_window],
        :priority_weight     => priority_stats[:weight],
        :priority_dependency => priority_stats[:dependency],
        :priority_exclusive  => priority_stats[:exclusive],
      }
    end

    private def validate_can_send_headers : Nil
      case @state
      when .idle?
      when .open?
      else
        raise StreamError.new("Cannot send HEADERS in state #{@state}", @id, ErrorCode::ProtocolError)
      end
    end

    private def validate_can_send_data : Nil
      unless can_send_data?
        raise StreamError.new("Cannot send DATA in state #{@state}", @id, ErrorCode::ProtocolError)
      end
    end

    private def validate_can_receive_headers : Nil
      case @state
      when .idle?
      when .open?
      when .half_closed_local?
      else
        raise StreamError.new("Cannot receive HEADERS in state #{@state}", @id, ErrorCode::ProtocolError)
      end
    end

    private def validate_can_receive_data : Nil
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
    end

    # Optimized state transition with validation
    private def transition_state(new_state : StreamState) : Nil
      valid_transitions = VALID_TRANSITIONS[@state]?
      unless valid_transitions && valid_transitions.includes?(new_state)
        raise StreamError.new("Invalid state transition from #{@state} to #{new_state}", @id, ErrorCode::ProtocolError)
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

    private def finalize_response : Nil
      if response = @response
        # Use to_s for text data - let Response handle the body content
        response.body = @incoming_data.to_s
        @response_channel.send(response)

        # Clear the memory buffer to free up resources
        @incoming_data = IO::Memory.new
      end
    end
  end
end
