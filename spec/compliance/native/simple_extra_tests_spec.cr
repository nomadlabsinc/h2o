require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC Extra Edge Case Tests" do
  # Extra test 1: Reserved bit handling
  it "handles frames with reserved bit set" do
    # First open stream 1
    headers = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    # Frame with reserved bit set in stream ID
    frame_bytes = Bytes[
      0x00, 0x00, 0x04,        # Length: 4
      0x00,                    # Type: DATA
      0x00,                    # Flags
      0x80, 0x00, 0x00, 0x01,  # Stream ID with reserved bit set
      0x74, 0x65, 0x73, 0x74   # "test"
    ]
    
    # Should ignore reserved bit and process normally
    expect_valid_frames([headers, frame_bytes])
  end
  
  # Extra test 2: Fragmented frames across network boundaries
  it "handles fragmented frame delivery" do
    # This simulates frames that might be split across TCP packets
    # Frame 1: Small HEADERS
    headers1 = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x88]  # Single indexed header
    )
    
    # Frame 2: Another small frame immediately after
    headers2 = build_raw_frame(
      length: 1,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 3_u32,
      payload: Bytes[0x88]
    )
    
    expect_valid_frames([headers1, headers2])
  end
  
  # Extra test 3: Maximum header list size
  it "handles maximum header list size limits" do
    # Large header block near limits
    large_header = Bytes.new(1000)
    large_header.fill(0x80_u8)  # Indexed headers
    
    headers_frame = build_raw_frame(
      length: large_header.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: large_header
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Extra test 4: Rapid stream creation and termination
  it "handles rapid stream lifecycle" do
    frames = [] of Bytes
    
    # Create and immediately close 10 streams
    (1..19).step(2) do |stream_id|
      # HEADERS with END_STREAM
      headers = build_raw_frame(
        length: 3,
        type: FRAME_TYPE_HEADERS,
        flags: FLAG_END_HEADERS | FLAG_END_STREAM,
        stream_id: stream_id.to_u32,
        payload: Bytes[0x82, 0x86, 0x84]
      )
      frames << headers
      
      # Immediate RST_STREAM (redundant but valid)
      rst = build_raw_frame(
        length: 4,
        type: FRAME_TYPE_RST_STREAM,
        flags: 0_u8,
        stream_id: stream_id.to_u32,
        payload: build_rst_stream_payload(ERROR_CANCEL)
      )
      frames << rst
    end
    
    expect_valid_frames(frames)
  end
  
  # Extra test 5: Edge cases in flow control
  it "handles flow control edge cases" do
    # WINDOW_UPDATE with maximum increment
    max_window = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 0_u32,
      payload: build_window_update_payload(0x7FFFFFFF_u32)  # Max value
    )
    
    # WINDOW_UPDATE with minimum non-zero increment
    min_window = build_raw_frame(
      length: 4,
      type: FRAME_TYPE_WINDOW_UPDATE,
      flags: 0_u8,
      stream_id: 1_u32,
      payload: build_window_update_payload(1_u32)  # Min value
    )
    
    expect_valid_frames([max_window, min_window])
  end
end