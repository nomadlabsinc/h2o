module H2O
  class Stream
    # Stream priority management following HTTP/2 specification
    # Handles stream dependencies, weights, and priority calculations
    class Prioritizer
      DEFAULT_WEIGHT =  16_u8
      MIN_WEIGHT     =   1_u8
      MAX_WEIGHT     = 255_u8

      property weight : UInt8
      property dependency : StreamId?
      property exclusive : Bool

      def initialize(@weight : UInt8 = DEFAULT_WEIGHT, @dependency : StreamId? = nil, @exclusive : Bool = false)
        validate_weight(@weight)
      end

      # Set priority with optional dependency and exclusivity
      def set_priority(weight : UInt8, dependency : StreamId? = nil, exclusive : Bool = false) : Nil
        validate_weight(weight)
        validate_dependency(dependency)

        @weight = weight
        @dependency = dependency
        @exclusive = exclusive
      end

      # Update just the weight
      def update_weight(new_weight : UInt8) : Nil
        validate_weight(new_weight)
        @weight = new_weight
      end

      # Update dependency stream
      def update_dependency(new_dependency : StreamId?, exclusive : Bool = false) : Nil
        validate_dependency(new_dependency)
        @dependency = new_dependency
        @exclusive = exclusive
      end

      # Calculate priority value for sorting (lower value = higher priority)
      def priority_value : Int32
        # Convert weight to priority value (higher weight = higher priority)
        # Use inverse of weight so that higher weights sort first
        (MAX_WEIGHT - @weight).to_i32
      end

      # Check if this stream has higher priority than another
      def higher_priority_than?(other : Prioritizer) : Bool
        priority_value < other.priority_value
      end

      # Check if this stream depends on another stream
      def depends_on?(stream_id : StreamId) : Bool
        @dependency == stream_id
      end

      # Check if this stream is independent (no dependencies)
      def independent? : Bool
        @dependency.nil?
      end

      # Create a PRIORITY frame for this stream
      def create_priority_frame(stream_id : StreamId) : PriorityFrame
        dependency = @dependency || 0_u32

        PriorityFrame.new(
          length: 5_u32,
          flags: 0_u8,
          stream_id: stream_id,
          exclusive: @exclusive,
          dependency: dependency,
          weight: @weight
        )
      end

      # Update priority from a PRIORITY frame
      def update_from_priority_frame(frame : PriorityFrame, stream_id : StreamId) : Nil
        # Validate that the frame is for this stream
        unless frame.stream_id == stream_id
          raise StreamError.new("PRIORITY frame stream ID mismatch", stream_id, ErrorCode::ProtocolError)
        end

        # Validate that stream doesn't depend on itself
        if frame.dependency == stream_id
          raise StreamError.new("Stream cannot depend on itself", stream_id, ErrorCode::ProtocolError)
        end

        set_priority(frame.weight, frame.dependency, frame.exclusive)
      end

      # Calculate relative priority for bandwidth allocation
      def relative_priority(total_weight : UInt32) : Float64
        return 1.0 if total_weight == 0
        @weight.to_f64 / total_weight.to_f64
      end

      # Check if priority configuration is valid
      def valid_priority? : Bool
        @weight >= MIN_WEIGHT && @weight <= MAX_WEIGHT
      end

      # Get priority information as a hash
      def to_hash : Hash(Symbol, UInt8 | StreamId | Bool | Nil)
        {
          :weight     => @weight,
          :dependency => @dependency,
          :exclusive  => @exclusive,
        }
      end

      # Compare two prioritizers for sorting
      def <=>(other : Prioritizer) : Int32
        # Primary sort: priority value (lower = higher priority)
        comparison = priority_value <=> other.priority_value
        return comparison unless comparison == 0

        # Secondary sort: dependency (independent streams first)
        if independent? && !other.independent?
          return -1
        elsif !independent? && other.independent?
          return 1
        end

        # Tertiary sort: exclusive streams first
        if @exclusive && !other.exclusive
          return -1
        elsif !@exclusive && other.exclusive
          return 1
        end

        # Final sort: by dependency ID (for deterministic ordering)
        (@dependency || 0_u32) <=> (other.dependency || 0_u32)
      end

      # Create a deep copy of this prioritizer
      def dup : Prioritizer
        Prioritizer.new(@weight, @dependency, @exclusive)
      end

      private def validate_weight(weight : UInt8) : Nil
        unless weight >= MIN_WEIGHT && weight <= MAX_WEIGHT
          raise ArgumentError.new("Invalid priority weight: #{weight}. Must be between #{MIN_WEIGHT} and #{MAX_WEIGHT}")
        end
      end

      private def validate_dependency(dependency : StreamId?) : Nil
        return if dependency.nil?

        if dependency == 0
          raise ArgumentError.new("Invalid dependency stream ID: 0. Stream ID must be non-zero")
        end

        # Additional validation could be added here for specific dependency constraints
      end
    end
  end
end
