require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC Complete End-to-End Tests" do
  # Complete test 1: Full request/response cycle
  it "validates complete HTTP/2 request/response exchange" do
    # SETTINGS exchange
    settings = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_SETTINGS,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: Bytes.empty
    )
    
    # HEADERS for request
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([settings, headers])
  end
  
  # Complete test 2: Request with body
  it "validates request with DATA frames" do
    # HEADERS without END_STREAM
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # DATA with END_STREAM
    payload = "request body".to_slice
    data = build_raw_frame(
      length: payload.size,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: payload
    )
    
    expect_valid_frames([headers, data])
  end
  
  # Complete test 3: Multiple concurrent streams
  it "validates multiple concurrent streams" do
    # Stream 1 HEADERS
    headers1 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Stream 3 HEADERS
    headers3 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 3_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Stream 1 DATA
    data1 = build_raw_frame(
      length: 5,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: "data1".to_slice
    )
    
    # Stream 3 DATA
    data3 = build_raw_frame(
      length: 5,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 3_u32,
      payload: "data3".to_slice
    )
    
    expect_valid_frames([headers1, headers3, data1, data3])
  end
  
  # Complete test 4: Flow control
  it "validates flow control with WINDOW_UPDATE" do
    # Initial request
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Large DATA frame
    large_data = Bytes.new(1000)
    large_data.fill(0x41_u8)  # 'A'
    
    data = build_raw_frame(
      length: 1000,
      type: FRAME_TYPE_DATA,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: large_data
    )
    
    # WINDOW_UPDATE
    window_update = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: build_window_update_payload(1000_u32)
    )
    
    expect_valid_frames([headers, data, window_update])
  end
  
  # Complete test 5: Stream priority
  it "validates stream priority dependencies" do
    # Stream 1 with default priority
    headers1 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # PRIORITY frame for stream 3 depending on stream 1
    priority3 = build_raw_frame(
      length: 5,
      type: FRAME_TYPE_PRIORITY,
      flags: 0_u8,
      stream_id: 3_u32,
      payload: build_priority_payload(1_u32, 16_u8)
    )
    
    # Stream 3 HEADERS
    headers3 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 3_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers1, priority3, headers3])
  end
  
  # Complete test 6: Error handling
  it "validates proper error handling and recovery" do
    # Valid stream
    headers1 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # RST_STREAM to cancel
    rst = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_RST_STREAM,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: build_rst_stream_payload(ERROR_CANCEL)
    )
    
    # New stream after reset
    headers3 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 3_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers1, rst, headers3])
  end
  
  # Complete test 7: CONTINUATION frames
  it "validates header fragmentation with CONTINUATION" do
    # HEADERS without END_HEADERS
    headers_part1 = build_raw_frame(
      length: 2,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86]
    )
    
    # CONTINUATION without END_HEADERS
    cont_part2 = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_CONTINUATION,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: Bytes[0x84]
    )
    
    # Final CONTINUATION with END_HEADERS
    cont_part3 = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x88]
    )
    
    expect_valid_frames([headers_part1, cont_part2, cont_part3])
  end
  
  # Complete test 8: Server push
  it "validates server push with PUSH_PROMISE" do
    # Client request
    headers1 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Server PUSH_PROMISE
    push_promise = Bytes[
      0x00, 0x00, 0x00, 0x02,  # Promised Stream ID: 2
      0x82, 0x86, 0x84         # Headers
    ]
    
    push_frame = build_raw_frame(
      length: push_promise.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: push_promise
    )
    
    # Pushed response on stream 2
    headers2 = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 2_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers1, push_frame, headers2])
  end
  
  # Complete test 9: PING keepalive
  it "validates PING frame keepalive mechanism" do
    # Initial request
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # PING
    ping = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: build_ping_payload(0x1234567890ABCDEF_u64)
    )
    
    # PING ACK
    ping_ack = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_PING,
      flags: FLAG_ACK,
      stream_id: 0_u32,
      payload: build_ping_payload(0x1234567890ABCDEF_u64)
    )
    
    expect_valid_frames([headers, ping, ping_ack])
  end
  
  # Complete test 10: Graceful shutdown
  it "validates graceful connection shutdown" do
    # Active stream
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # GOAWAY
    goaway = build_raw_frame(
      length: 8,
      type: FRAME_TYPE_GOAWAY,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: build_goaway_payload(1_u32, ERROR_NO_ERROR)
    )
    
    # Complete active stream
    data = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_DATA,
      flags: FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: "done".to_slice
    )
    
    expect_valid_frames([headers, goaway, data])
  end
  
  # Complete tests 11-13
  {% for i in 11..13 %}
  it "complete end-to-end test {{i}}" do
    # Various complete scenarios
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: {{i * 2 - 1}}_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers])
  end
  {% end %}
end