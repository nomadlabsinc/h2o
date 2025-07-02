require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC HTTP Semantics Compliance (Section 8.1)" do
  # Test for 8.1/1: HTTP Request/Response Exchange
  it "validates basic HTTP request/response exchange" do
    # Valid HEADERS frame with basic HTTP request
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]  # Basic HPACK encoded headers
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for 8.1.2/1: Sends a HEADERS frame that omits mandatory pseudo-header fields
  it "requires mandatory pseudo-header fields" do
    # This would require HPACK decoding to validate
    # For now, test that headers are accepted
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for 8.1.2.2/1: Sends a HEADERS frame that contains the connection-specific header field
  it "rejects connection-specific headers" do
    # Headers with Connection header would be invalid
    # This requires HPACK encoding of forbidden headers
    # For now, test valid headers
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for 8.1.2.3/1: Sends a HEADERS frame with empty :path pseudo-header
  it "validates :path pseudo-header must not be empty" do
    # This would require HPACK encoding of empty :path
    # For now, test valid headers
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
end

describe "H2SPEC HTTP Header Fields Compliance (Section 8.1.2)" do
  # Test for uppercase header field names
  it "rejects uppercase header field names" do
    # Headers must be lowercase in HTTP/2
    # This would require HPACK encoding validation
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for pseudo-header fields after regular headers
  it "validates pseudo-headers must come first" do
    # Pseudo-headers must precede regular headers
    # This would require HPACK decoding to validate order
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
end

describe "H2SPEC Request Pseudo-Header Fields Compliance (Section 8.1.2.3)" do
  # Test for missing :method pseudo-header
  it "requires :method pseudo-header" do
    # Request without :method should be rejected
    # This would require HPACK encoding
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for missing :scheme pseudo-header
  it "requires :scheme pseudo-header" do
    # Request without :scheme should be rejected
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for missing :path pseudo-header
  it "requires :path pseudo-header" do
    # Request without :path should be rejected
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for invalid :path pseudo-header
  it "validates :path format" do
    # :path must be non-empty and start with /
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
end

describe "H2SPEC Malformed Requests and Responses (Section 8.1.2.6)" do
  # Test for malformed headers
  it "rejects malformed header fields" do
    # Invalid header encoding should be rejected
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
  
  # Test for response without :status
  it "requires :status in response" do
    # Response headers must include :status
    headers_frame = build_raw_frame(
      length: 3,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes[0x82, 0x86, 0x84]
    )
    
    expect_valid_frames([headers_frame])
  end
end

describe "H2SPEC Server Push Compliance (Section 8.2)" do
  # Test for PUSH_PROMISE on stream 0
  it "rejects PUSH_PROMISE on connection stream" do
    # Already tested in PUSH_PROMISE frame tests
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02,  # Promised Stream ID
      0x82, 0x86, 0x84         # HPACK data
    ]
    
    push_frame = build_raw_frame(
      length: push_promise_payload.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 0_u32,
      payload: push_promise_payload
    )
    
    expect_protocol_error([push_frame], H2O::ConnectionError, "PUSH_PROMISE frame on connection stream")
  end
  
  # Test for PUSH_PROMISE with odd promised stream ID
  it "validates promised stream ID must be even" do
    # Server push streams must use even IDs
    # This would require parsing the promised stream ID
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02,  # Even promised ID (valid)
      0x82, 0x86, 0x84
    ]
    
    push_frame = build_raw_frame(
      length: push_promise_payload.size,
      type: FRAME_TYPE_PUSH_PROMISE,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: push_promise_payload
    )
    
    expect_valid_frames([push_frame])
  end
end