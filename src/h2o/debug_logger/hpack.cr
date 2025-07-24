# Debug instrumentation for HPACK operations
{% if flag?(:h2o_debug) %}
  module H2O
    module HPACK
      # Example: Add debug instrumentation for encoder operations
      # class Encoder
      #   def encode_original(headers)
      #     # Original implementation would be called here
      #   end
      #
      #   def encode(headers)
      #     start_time = Time.monotonic
      #     H2O::Log.debug { "[HPACK] Starting header encoding for #{headers.size} headers" }
      #
      #     result = encode_original(headers)
      #
      #     duration = Time.monotonic - start_time
      #     H2O::Log.debug { "[HPACK] Completed encoding in #{"%.2f" % duration.total_milliseconds}ms (#{result.size} bytes)" }
      #
      #     result
      #   end
      # end
    end
  end
{% end %}
