# HTTP/2 Protocol Violation Handling Guide for H2O

Based on analysis of Go's `net/http2` and Rust's `h2` libraries, this guide outlines how H2O should handle protocol violations to achieve compliance.

## Key Principles

### 1. Fail Fast and Strictly
Unlike H2O's current resilient approach, compliant clients must detect and reject protocol violations immediately.

### 2. Proper Error Classification
- **Connection Errors**: Send GOAWAY and close connection
- **Stream Errors**: Send RST_STREAM for the specific stream
- **User Errors**: Return appropriate error to application

### 3. State Machine Enforcement
Strictly enforce HTTP/2 state transitions and reject invalid frame sequences.

## Required Changes for H2O

### Frame Validation (CRITICAL)

```crystal
# Current: Too lenient
frame = Frame.from_io(io, max_frame_size)

# Required: Strict validation with immediate failure
def self.from_io(io : IO, max_frame_size : UInt32) : Frame
  # Validate frame size BEFORE reading payload
  if length > max_frame_size
    raise FrameError.new("Frame size #{length} exceeds maximum #{max_frame_size}")
  end
  
  # Validate stream ID constraints per frame type
  validate_stream_id_for_frame_type(frame_type, stream_id)
  
  # Create frame with validation
  create_frame(frame_type, length, flags, stream_id, payload)
end
```

### Settings Validation (HIGH PRIORITY)

```crystal
# Add to handle_settings_frame:
def validate_settings_value(identifier : SettingIdentifier, value : UInt32)
  case identifier
  when .enable_push?
    if value != 0 && value != 1
      send_goaway(ErrorCode::ProtocolError)
      raise ProtocolError.new("SETTINGS_ENABLE_PUSH must be 0 or 1")
    end
  when .initial_window_size?
    if value > 0x7fffffff_u32
      send_goaway(ErrorCode::FlowControlError) 
      raise FlowControlError.new("SETTINGS_INITIAL_WINDOW_SIZE exceeds maximum")
    end
  when .max_frame_size?
    if value < 16384_u32 || value > 16777215_u32
      send_goaway(ErrorCode::ProtocolError)
      raise ProtocolError.new("SETTINGS_MAX_FRAME_SIZE out of range")
    end
  end
end
```

### Stream State Validation (HIGH PRIORITY)

```crystal
# Enhance Stream class validation
def receive_data(frame : DataFrame)
  # Check if we can receive DATA in current state
  unless can_receive_data?
    case @state
    when .half_closed_remote?, .closed?
      raise StreamError.new("Cannot receive DATA in state #{@state}", @id, ErrorCode::StreamClosed)
    when .idle?
      raise ConnectionError.new("DATA frame on idle stream #{@id}", ErrorCode::ProtocolError)
    end
  end
  
  validate_flow_control(frame.data.size)
  # ... rest of processing
end
```

### Frame Type-Specific Validation

```crystal
# Add validation for each frame type
module FrameValidation
  def self.validate_data_frame(frame : DataFrame)
    if frame.stream_id == 0
      raise ConnectionError.new("DATA frame with stream ID 0", ErrorCode::ProtocolError)
    end
  end
  
  def self.validate_headers_frame(frame : HeadersFrame) 
    if frame.stream_id == 0
      raise ConnectionError.new("HEADERS frame with stream ID 0", ErrorCode::ProtocolError)
    end
  end
  
  def self.validate_ping_frame(frame : PingFrame)
    if frame.stream_id != 0
      raise ConnectionError.new("PING frame with non-zero stream ID", ErrorCode::ProtocolError)
    end
    if frame.length != 8
      raise ConnectionError.new("PING frame invalid length", ErrorCode::FrameSizeError)
    end
  end
end
```

### Error Response Strategy

```crystal
# Proper error handling in handle_frame
private def handle_frame(frame : Frame)
  begin
    # Validate frame before processing
    validate_frame_constraints(frame)
    
    case frame
    when DataFram
      FrameValidation.validate_data_frame(frame)
      handle_data_frame(frame)
    when HeadersFrame
      FrameValidation.validate_headers_frame(frame)
      handle_headers_frame(frame)
    # ... other frame types
    end
  rescue ConnectionError => ex
    send_goaway(ex.error_code)
    @closed = true
    raise ex
  rescue StreamError => ex  
    send_rst_stream(ex.stream_id, ex.error_code)
    @stream_pool.remove_stream(ex.stream_id)
    # Don't re-raise - connection continues
  end
end
```

## Implementation Priority

### Phase 1 (Immediate)
1. Add strict frame size validation
2. Implement SETTINGS parameter validation
3. Add stream ID constraints for each frame type

### Phase 2 (High Priority)
1. Enforce stream state machine
2. Add HPACK validation
3. Implement proper pseudo-header validation

### Phase 3 (Medium Priority)
1. Add flow control validation
2. Implement CONTINUATION frame validation
3. Add header list size limits

### Phase 4 (Lower Priority)
1. Add all remaining frame-specific validations
2. Implement comprehensive error reporting
3. Add performance optimizations

## Testing Strategy

Each validation should be tested with the h2-client-test-harness to ensure:
1. Valid frames are processed correctly
2. Invalid frames trigger appropriate errors
3. Error codes match RFC 7540 requirements
4. Connection/stream state is properly maintained

## Expected Results

After implementing these changes, H2O should achieve significantly higher compliance rates:
- Frame validation tests should pass (4.x series)
- Settings validation tests should pass (6.5.x series)
- Stream state tests should pass (5.1.x series)
- Overall compliance should improve from 0% to 80%+ initially

The goal is to be as strict as Go's `net/http2` and Rust's `h2` while maintaining good performance.