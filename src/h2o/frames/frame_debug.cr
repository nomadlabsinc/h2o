{% if flag?(:h2o_debug) %}
module H2O
  abstract class Frame
    # Store reference to original method before we override it
    def self.from_io_original(io : IO, max_frame_size : UInt32 = MAX_FRAME_SIZE) : Frame
      from_io_with_buffer_pool(io, max_frame_size)
    end

    # Debug wrapper that replaces the original from_io method
    def self.from_io(io : IO, max_frame_size : UInt32 = MAX_FRAME_SIZE) : Frame
      start_time = Time.monotonic
      H2O::Log.debug { "[FRAME] Starting frame parse from IO" }
      
      # Call the original implementation
      frame = from_io_original(io, max_frame_size)
      
      duration = Time.monotonic - start_time
      H2O::Log.debug { "[FRAME] Completed #{frame.class} parse in #{"%.2f" % duration.total_milliseconds}ms (Length: #{frame.length}, Stream: #{frame.stream_id})" }
      
      frame
    end
  end
end
{% end %}