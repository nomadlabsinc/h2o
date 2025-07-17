module H2O
  class Connection
    # Connection settings management following HTTP/2 specification
    # Encapsulates local and remote settings for a connection
    class Settings
      # HTTP/2 settings identifiers (RFC 7540 Section 6.5.2)
      HEADER_TABLE_SIZE      = 0x1_u16
      ENABLE_PUSH            = 0x2_u16
      MAX_CONCURRENT_STREAMS = 0x3_u16
      INITIAL_WINDOW_SIZE    = 0x4_u16
      MAX_FRAME_SIZE         = 0x5_u16
      MAX_HEADER_LIST_SIZE   = 0x6_u16

      # Default values as per RFC 7540
      property header_table_size : UInt32 = 4096_u32
      property enable_push : Bool = false # Client doesn't support server push
      property max_concurrent_streams : UInt32 = 100_u32
      property initial_window_size : UInt32 = 65535_u32
      property max_frame_size : UInt32 = 16384_u32
      property max_header_list_size : UInt32 = 8192_u32

      def initialize
      end

      # Convert settings to hash format for SETTINGS frames
      def to_hash : Hash(UInt16, UInt32)
        {
          HEADER_TABLE_SIZE      => @header_table_size,
          ENABLE_PUSH            => @enable_push ? 1_u32 : 0_u32,
          MAX_CONCURRENT_STREAMS => @max_concurrent_streams,
          INITIAL_WINDOW_SIZE    => @initial_window_size,
          MAX_FRAME_SIZE         => @max_frame_size,
          MAX_HEADER_LIST_SIZE   => @max_header_list_size,
        }
      end

      # Update settings from received SETTINGS frame
      def update_from_hash(settings : Hash(UInt16, UInt32)) : Nil
        settings.each do |identifier, value|
          case identifier
          when HEADER_TABLE_SIZE
            @header_table_size = value
          when ENABLE_PUSH
            @enable_push = value != 0
          when MAX_CONCURRENT_STREAMS
            @max_concurrent_streams = value
          when INITIAL_WINDOW_SIZE
            validate_window_size(value)
            @initial_window_size = value
          when MAX_FRAME_SIZE
            validate_frame_size(value)
            @max_frame_size = value
          when MAX_HEADER_LIST_SIZE
            @max_header_list_size = value
          end
        end
      end

      # Validate settings according to HTTP/2 specification
      def validate : Nil
        validate_window_size(@initial_window_size)
        validate_frame_size(@max_frame_size)

        if @max_concurrent_streams == 0
          raise ConnectionError.new("MAX_CONCURRENT_STREAMS cannot be 0", ErrorCode::ProtocolError)
        end
      end

      private def validate_window_size(size : UInt32) : Nil
        if size > 0x7fffffff_u32
          raise ConnectionError.new("Window size exceeds maximum: #{size}", ErrorCode::FlowControlError)
        end
      end

      private def validate_frame_size(size : UInt32) : Nil
        if size < 16384_u32 || size > 16777215_u32
          raise ConnectionError.new("Invalid frame size: #{size}", ErrorCode::ProtocolError)
        end
      end
    end
  end
end
