# HTTP/2 Channel Implementation Analysis

## Issue Summary

The integration tests are failing with `Channel::ClosedError` originating from the connection dispatcher's `select` operations at `src/h2o/connection.cr:157`. This indicates a race condition in the fiber coordination and channel lifecycle management.

## Root Cause Analysis

### 1. **Channel Lifecycle Race Condition**

**Location**: `Connection.close()` method (lines 89-99)
```crystal
def close : Nil
  return if @closed
  @closed = true
  goaway_frame = GoawayFrame.new(@last_stream_id, ErrorCode::NoError)
  send_frame(goaway_frame)
  @outgoing_frames.close    # ← Channel closed here
  @incoming_frames.close    # ← Channel closed here
  @socket.close
end
```

**Problem**: Channels are closed immediately while background fibers are still running `select` operations on them.

### 2. **Fiber Coordination Issues**

**Affected Fibers**:
- **Reader Fiber** (lines 120-136): Continues running and may try to send to `@incoming_frames` after closure
- **Writer Fiber** (lines 138-153): Uses `select` with timeout on `@outgoing_frames` after closure
- **Dispatcher Fiber** (lines 155-164): Uses `select` with timeout on `@incoming_frames` after closure

**Problem**: No proper fiber shutdown coordination before closing channels.

### 3. **Select Timeout Race Condition**

**Location**: Dispatcher loop (lines 157-158)
```crystal
select
when frame = @incoming_frames.receive  # ← Can fail if channel closed
  handle_frame(frame)
when timeout(1.second)
  break if @closed
end
```

**Problem**: The `@incoming_frames.receive` can throw `Channel::ClosedError` if the channel is closed between the `select` evaluation and the actual receive operation.

### 4. **Client Timeout Implementation Issues**

**Location**: `Client.with_timeout()` method (lines 134-163)
```crystal
private def with_timeout(timeout : Time::Span, &block)
  # Spawns additional fiber without cleanup coordination
  spawn do
    begin
      result = block.call
    rescue ex
      exception = ex
    end
  end
  # ... polling loop
end
```

**Problem**: Creates additional fibers that may outlive the connection, leading to resource leaks and channel access after closure.

## Technical Issues Identified

### 1. **Missing Fiber Cleanup**
- No mechanism to wait for background fibers to complete before closing channels
- Fibers continue running after connection is marked as closed
- No proper shutdown signal coordination

### 2. **Channel State Management**
- Channels closed abruptly without ensuring all pending operations complete
- No buffering or graceful drain of pending frames
- Missing error handling for closed channel scenarios

### 3. **Stream Response Coordination**
- Streams wait on `@response_channel.receive` which may never complete if connection fails
- No timeout mechanism for individual stream responses
- Missing connection failure propagation to waiting streams

## Proposed Fixes

### 1. **Implement Graceful Fiber Shutdown**

```crystal
def close : Nil
  return if @closed
  @closed = true

  # Send GOAWAY frame first
  goaway_frame = GoawayFrame.new(@last_stream_id, ErrorCode::NoError)
  send_frame(goaway_frame)

  # Wait for background fibers to complete
  wait_for_fiber_completion

  # Then close channels and socket
  @outgoing_frames.close
  @incoming_frames.close
  @socket.close
end

private def wait_for_fiber_completion : Nil
  # Allow time for fibers to see @closed flag and exit gracefully
  timeout = 1.second
  start_time = Time.monotonic

  while (@reader_fiber&.running? || @writer_fiber&.running? || @dispatcher_fiber&.running?)
    break if Time.monotonic - start_time > timeout
    Fiber.yield
  end
end
```

### 2. **Add Channel Error Handling in Select Operations**

```crystal
private def dispatcher_loop : Nil
  loop do
    break if @closed

    begin
      select
      when frame = @incoming_frames.receive
        handle_frame(frame)
      when timeout(1.second)
        break if @closed
      end
    rescue Channel::ClosedError
      Log.debug { "Dispatcher channel closed, exiting loop" }
      break
    end
  end
end

private def writer_loop : Nil
  loop do
    break if @closed

    begin
      select
      when frame = @outgoing_frames.receive
        # ... write frame
      when timeout(1.second)
        break if @closed
      end
    rescue Channel::ClosedError
      Log.debug { "Writer channel closed, exiting loop" }
      break
    end
  end
end
```

### 3. **Fix Stream Response Timeout**

```crystal
def await_response : Response?
  select
  when response = @response_channel.receive
    response
  when timeout(30.seconds)  # Configurable timeout
    Log.warn { "Stream #{@id} response timeout" }
    nil
  end
rescue Channel::ClosedError
  Log.debug { "Stream #{@id} channel closed before response" }
  nil
end
```

### 4. **Improve Client Timeout Implementation**

```crystal
private def with_timeout(timeout : Time::Span, &block)
  done_channel = Channel(Bool).new(1)
  result = nil
  exception = nil

  fiber = spawn do
    begin
      result = block.call
    rescue ex
      exception = ex
    ensure
      done_channel.send(true)
    end
  end

  select
  when done_channel.receive
    # Operation completed
  when timeout(timeout)
    # Force cleanup of spawned fiber if needed
    raise TimeoutError.new("Operation timed out after #{timeout}")
  end

  if ex = exception
    raise ex
  end

  result
end
```

### 5. **Add Connection State Validation**

```crystal
private def send_frame(frame : Frame) : Nil
  if @closed
    Log.warn { "Attempted to send frame on closed connection" }
    return
  end

  begin
    @outgoing_frames.send(frame)
  rescue Channel::ClosedError
    Log.warn { "Cannot send frame: connection closed" }
  end
end
```

## Testing Strategy

### 1. **Unit Tests for Channel Lifecycle**
- Test graceful connection closure under load
- Verify fiber cleanup completion
- Test channel error handling scenarios

### 2. **Integration Tests for Timeout Scenarios**
- Test client timeout behavior with slow servers
- Verify connection cleanup after timeouts
- Test multiple concurrent requests during connection closure

### 3. **Stress Tests for Concurrency**
- Multiple simultaneous connections
- High-frequency connection open/close cycles
- Resource leak detection

## Implementation Priority

1. **High Priority**: Fix select operation error handling (#2)
2. **High Priority**: Implement graceful fiber shutdown (#1)
3. **Medium Priority**: Fix stream response timeout (#3)
4. **Medium Priority**: Improve client timeout implementation (#4)
5. **Low Priority**: Add connection state validation (#5)

## Expected Outcome

After implementing these fixes:
- Integration tests should pass consistently
- No more `Channel::ClosedError` exceptions
- Proper resource cleanup on connection termination
- Improved error handling and debugging information
- Better timeout behavior for slow or unresponsive servers
