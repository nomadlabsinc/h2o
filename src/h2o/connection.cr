require "./frames/frame_reader"
require "./frames/frame_writer"
require "./hpack/encoder"
require "./hpack/decoder"
require "./connection/settings"
require "./connection/flow_control"
require "./types"
require "./preface"

module H2O
  # H2O::Connection manages HTTP/2 connection-level state and coordination
  # This class acts as the central coordinator for all streams on a single HTTP/2 connection
  # (Layer 4 of the SRP refactor)
  class Connection
    property socket : TlsSocket | TcpSocket
    property frame_reader : FrameReader
    property frame_writer : FrameWriter
    property hpack_encoder : HPACK::Encoder
    property hpack_decoder : HPACK::Decoder
    property local_settings : Connection::Settings
    property remote_settings : Connection::Settings
    property flow_control : Connection::FlowControl
    property closed : Bool
    property closing : Bool
    property current_stream_id : StreamId

    def initialize(@socket : TlsSocket | TcpSocket)
      @frame_reader = FrameReader.new(@socket.to_io)
      @frame_writer = FrameWriter.new(@socket.to_io)
      @hpack_encoder = HPACK::Encoder.new
      @hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
      @local_settings = Connection::Settings.new
      @remote_settings = Connection::Settings.new
      @flow_control = Connection::FlowControl.new
      @closed = false
      @closing = false
      @current_stream_id = 1_u32
    end

    # Initialize HTTP/2 connection with preface exchange
    def initialize_connection : Nil
      send_connection_preface
      validate_server_preface
    end

    # Send HTTP/2 connection preface and initial SETTINGS
    def send_connection_preface : Nil
      # Send the HTTP/2 connection preface
      Preface.send_preface(@socket.to_io)

      # Send initial SETTINGS frame
      settings_frame = SettingsFrame.new(
        length: 0_u32,
        flags: 0_u8,
        stream_id: 0_u32,
        settings: @local_settings.to_hash
      )
      send_frame(settings_frame)
    end

    # Validate server preface (must receive SETTINGS frame)
    def validate_server_preface : Bool
      frame = receive_frame
      return false unless frame.is_a?(SettingsFrame)

      handle_settings_frame(frame)
      send_settings_ack
      true
    end

    # Send a frame through the connection
    def send_frame(frame : Frame) : Nil
      @frame_writer.write_frame(frame)
    end

    # Receive a frame from the connection
    def receive_frame : Frame
      @frame_reader.read_frame
    end

    # Handle connection-level frames
    def handle_connection_frame(frame : Frame) : Nil
      case frame
      when SettingsFrame
        handle_settings_frame(frame)
      when PingFrame
        handle_ping_frame(frame)
      when GoawayFrame
        handle_goaway_frame(frame)
      when WindowUpdateFrame
        handle_window_update_frame(frame) if frame.stream_id == 0
      end
    end

    # Get next stream ID for client-initiated streams
    def next_stream_id : StreamId
      stream_id = @current_stream_id
      @current_stream_id += 2
      stream_id
    end

    # Close the connection gracefully
    def close : Nil
      return if @closed

      # Send GOAWAY frame if not already closing
      unless @closing
        @closing = true
        goaway_frame = GoawayFrame.new(
          length: 8_u32,
          flags: 0_u8,
          stream_id: 0_u32,
          last_stream_id: @current_stream_id - 2,
          error_code: ErrorCode::NoError.value.to_u32,
          debug_data: Bytes.empty
        )
        send_frame(goaway_frame)
      end

      @closed = true
      @socket.close
    end

    # Check if connection is closed
    def closed? : Bool
      @closed || @socket.closed?
    end

    private def handle_settings_frame(frame : SettingsFrame) : Nil
      return if frame.ack?

      # Update remote settings
      @remote_settings.update_from_hash(frame.settings)

      # Handle settings that affect local state
      frame.settings.each do |identifier, value|
        case identifier
        when Connection::Settings::HEADER_TABLE_SIZE
          @hpack_encoder.set_max_table_size(value)
        when Connection::Settings::INITIAL_WINDOW_SIZE
          # Update flow control window size
          @flow_control.update_initial_window_size(value.to_i32)
        end
      end
    end

    private def handle_ping_frame(frame : PingFrame) : Nil
      unless frame.ack?
        # Send PING ACK
        ping_ack = PingFrame.new(
          length: 8_u32,
          flags: PingFrame::ACK,
          stream_id: 0_u32,
          data: frame.data
        )
        send_frame(ping_ack)
      end
    end

    private def handle_goaway_frame(frame : GoawayFrame) : Nil
      @closing = true
      # Connection will be closed by the peer
    end

    private def handle_window_update_frame(frame : WindowUpdateFrame) : Nil
      @flow_control.update_window(frame.increment)
    end

    private def send_settings_ack : Nil
      ack_frame = SettingsFrame.new(
        length: 0_u32,
        flags: SettingsFrame::ACK,
        stream_id: 0_u32,
        settings: {} of UInt16 => UInt32
      )
      send_frame(ack_frame)
    end
  end
end
