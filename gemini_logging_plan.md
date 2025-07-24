# Plan for Implementing Performance-Conscious Debug Logging

This document outlines the plan to add detailed, opt-in debug logging to the `h2o` Crystal project. The primary goals are to provide insightful logging for debugging while ensuring zero performance impact when the feature is disabled.

## 1. Rationale

Detailed logging of HTTP/2 frame processing is invaluable for debugging complex interactions, performance tuning, and identifying protocol-level issues. However, unconditional logging in a high-performance library like `h2o` would introduce unacceptable overhead.

This plan implements a conditional logging mechanism that is disabled by default and can be enabled at runtime via an environment variable (`H2O_DEBUG`). The implementation will use techniques to ensure that when logging is disabled, the performance cost is negligible.

## 2. Implementation Plan

### Step 2.1: Create the `DebugLogger` Module

A new file, `src/h2o/debug_logger.cr`, will be created to encapsulate the debug logging logic.

```crystal
# src/h2o/debug_logger.cr
require "log"

module H2O
  # A performance-conscious logger for detailed debugging.
  #
  # This logger is controlled by the `H2O_DEBUG` environment variable.
  # When disabled, logging calls compile down to a single, cached boolean check,
  # ensuring negligible performance impact in production.
  #
  # To enable, set `H2O_DEBUG=true` (or `1`, `yes`, `on`).
  #
  # Usage:
  #   H2O::DebugLogger.log "CONTEXT", "My debug message"
  #
  module DebugLogger
    # Cache the result of the ENV check for performance.
    @@enabled : Bool? = nil

    # Checks if debug logging is enabled. The result is cached after the first call.
    def self.enabled? : Bool
      if enabled = @@enabled
        return enabled
      end
      @@enabled = H2O.env_flag_enabled?("H2O_DEBUG")
    end

    # Logs a message if debug logging is enabled.
    #
    # The block is only evaluated if logging is active.
    macro log(context, message)
      if H2O::DebugLogger.enabled?
        # Use the existing Log backend for h2o
        H2O::Log.debug { "[#{ {{context}} }] #{ {{message}} }" }
      end
    end
  end
end
```

### Step 2.2: Integrate the Logger

The new module will be integrated into the project by adding a `require` statement in the main `src/h2o.cr` file.

```crystal
# src/h2o.cr (partial)
require "./h2o/version"
require "./h2o/debug_logger" # Add this line
require "./h2o/exceptions"
# ... rest of the file
```

### Step 2.3: Add Logging to Frame Parsing Logic

The core frame parsing method, `H2O::Frame.from_io_with_buffer_pool`, will be instrumented with logging calls.

File to modify: `src/h2o/frames/frame.cr`

```crystal
# src/h2o/frames/frame.cr (partial)
# In H2O::Frame.from_io_with_buffer_pool
def self.from_io_with_buffer_pool(io : IO, max_frame_size : UInt32 = MAX_FRAME_SIZE) : Frame
  # Start total time measurement if logging is enabled
  total_start_time = Time.monotonic if H2O::DebugLogger.enabled?
  H2O::DebugLogger.log "FRAME", "Reading HTTP/2 frame header (9 bytes)"

  # Read frame header
  header_start_time = Time.monotonic if H2O::DebugLogger.enabled?
  header = Bytes.new(FRAME_HEADER_SIZE)
  io.read_fully(header)
  if H2O::DebugLogger.enabled?
    header_duration = Time.monotonic - header_start_time
    H2O::DebugLogger.log "FRAME", "Header read complete in #{"%.2f" % header_duration.total_milliseconds}ms"
  end

  length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
  frame_type = FrameType.new(header[3])
  flags = header[4]
  stream_id = ((header[5].to_u32 << 24) | (header[6].to_u32 << 16) | (header[7].to_u32 << 8) | header[8].to_u32) & 0x7fffffff_u32

  H2O::DebugLogger.log "FRAME", "Parsed header - Type: #{frame_type}, Length: #{length}, Stream: #{stream_id}, Flags: 0x#{flags.to_s(16)}"

  # ... (validation logic remains here) ...

  # Read payload
  H2O::DebugLogger.log "FRAME", "Reading payload (#{length} bytes)"
  payload_start_time = Time.monotonic if H2O::DebugLogger.enabled?
  payload = if length > 0
              # ... (payload reading logic) ...
            else
              Bytes.empty
            end
  if H2O::DebugLogger.enabled?
    payload_duration = Time.monotonic - payload_start_time
    H2O::DebugLogger.log "FRAME", "Payload read complete in #{"%.2f" % payload_duration.total_milliseconds}ms"
  end

  frame = create_frame(frame_type, length, flags, stream_id, payload)

  # ... (comprehensive validation remains here) ...

  if H2O::DebugLogger.enabled?
    total_duration = Time.monotonic - total_start_time
    H2O::DebugLogger.log "FRAME", "Complete frame processed in #{"%.2f" % total_duration.total_milliseconds}ms - #{frame.class}"
  end

  frame
end
```
*(Note: The actual implementation will be slightly different to avoid multiple `if H2O::DebugLogger.enabled?` checks where possible, but this illustrates the intent.)*

## 3. Testing Plan

A new test file, `spec/h2o/debug_logger_spec.cr`, will be created to verify the functionality.

### Test Case 3.1: Logging is Disabled by Default

*   **Description:** Verifies that no debug logs are produced when `H2O_DEBUG` is not set.
*   **Steps:**
    1.  Ensure `H2O_DEBUG` is unset.
    2.  Redirect the `Log.io` to an in-memory `IO::Memory`.
    3.  Call a function that uses `H2O::DebugLogger.log`.
    4.  Assert that `H2O::DebugLogger.enabled?` is `false`.
    5.  Assert that the `IO::Memory` buffer is empty.

### Test Case 3.2: Logging is Enabled by `H2O_DEBUG`

*   **Description:** Verifies that debug logs are produced when `H2O_DEBUG` is set to a truthy value.
*   **Steps:**
    1.  Set `ENV["H2O_DEBUG"] = "true"`.
    2.  Reset the `DebugLogger`'s cached `@@enabled` flag to force a re-read of the ENV var.
    3.  Redirect `Log.io` to an `IO::Memory`.
    4.  Call a function that uses `H2O::DebugLogger.log` (e.g., parse a test frame).
    5.  Assert that `H2O::DebugLogger.enabled?` is `true`.
    6.  Assert that the `IO::Memory` buffer contains the expected log messages (e.g., `"[FRAME] Reading HTTP/2 frame header"`).
    7.  Clean up by unsetting the ENV var and resetting the logger cache.

### Test Case 3.3: `enabled?` Flag Caching

*   **Description:** Verifies that the `H2O_DEBUG` environment variable is only checked once for performance.
*   **Steps:**
    1.  Set `ENV["H2O_DEBUG"] = "true"`.
    2.  Reset the logger cache.
    3.  Call `H2O::DebugLogger.enabled?` and assert it returns `true`.
    4.  Change the environment variable: `ENV["H2O_DEBUG"] = "false"`.
    5.  Call `H2O::DebugLogger.enabled?` again.
    6.  Assert that it still returns `true`, proving the value was cached and the ENV was not re-checked.
    7.  Clean up.

### Test Case 3.4: Zero Performance Overhead (Design Verification)

*   **Description:** This is a design principle verification rather than a functional test.
*   **Assertion:** The implementation of the `log` macro uses an `if H2O::DebugLogger.enabled?` check. When logging is disabled, this check is a single, fast boolean comparison. The code inside the `if` block, including string interpolation and the call to `H2O::Log.debug`, is never executed. This design inherently guarantees near-zero overhead when logging is disabled. This will be documented in a comment in the test file.
