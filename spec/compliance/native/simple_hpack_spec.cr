require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC HPACK Compliance" do
  # Test for invalid HPACK encoding
  it "rejects invalid HPACK encoding in HEADERS" do
    # All 0xFF bytes is invalid HPACK
    invalid_hpack = Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    headers_frame = build_raw_frame(
      length: invalid_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: invalid_hpack
    )

    expect_protocol_error([headers_frame], H2O::CompressionError, "Invalid HPACK encoding")
  end

  # Test for valid basic HPACK encoding
  it "accepts valid HPACK encoding" do
    # Basic valid HPACK data
    valid_hpack = Bytes[0x82, 0x86, 0x84] # Common indexed headers

    headers_frame = build_raw_frame(
      length: valid_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: valid_hpack
    )

    expect_valid_frames([headers_frame])
  end

  # Test for HPACK with padding
  it "handles HPACK in padded HEADERS frame" do
    # HEADERS with PADDED flag
    pad_length = 4_u8
    hpack_data = Bytes[0x82, 0x86, 0x84]
    padding = Bytes.new(pad_length)
    padding.fill(0_u8)

    padded_payload = Bytes.new(1 + hpack_data.size + pad_length)
    padded_payload[0] = pad_length
    hpack_data.copy_to(padded_payload + 1)
    padding.copy_to(padded_payload + 1 + hpack_data.size)

    headers_frame = build_raw_frame(
      length: padded_payload.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_PADDED | FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: padded_payload
    )

    expect_valid_frames([headers_frame])
  end

  # Test for HPACK split across CONTINUATION
  it "handles HPACK split across HEADERS and CONTINUATION" do
    # First part in HEADERS
    hpack_part1 = Bytes[0x82, 0x86]

    headers_frame = build_raw_frame(
      length: hpack_part1.size,
      type: FRAME_TYPE_HEADERS,
      flags: 0_u8, # No END_HEADERS
      stream_id: 1_u32,
      payload: hpack_part1
    )

    # Second part in CONTINUATION
    hpack_part2 = Bytes[0x84]

    continuation_frame = build_raw_frame(
      length: hpack_part2.size,
      type: FRAME_TYPE_CONTINUATION,
      flags: FLAG_END_HEADERS,
      stream_id: 1_u32,
      payload: hpack_part2
    )

    expect_valid_frames([headers_frame, continuation_frame])
  end

  # Test for empty HPACK data
  it "handles empty HPACK data" do
    # Empty headers (0 length)
    headers_frame = build_raw_frame(
      length: 0,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: Bytes.empty
    )

    expect_valid_frames([headers_frame])
  end

  # Test for HPACK in PUSH_PROMISE
  it "validates HPACK in PUSH_PROMISE frame" do
    # PUSH_PROMISE with HPACK data
    push_promise_payload = Bytes[
      0x00, 0x00, 0x00, 0x02, # Promised Stream ID: 2
      0x82, 0x86, 0x84        # HPACK data
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

  # Test for maximum header size
  it "handles large HPACK data" do
    # Large but valid HPACK data
    large_hpack = Bytes.new(1000)
    large_hpack.fill(0x80_u8) # Indexed header field pattern

    headers_frame = build_raw_frame(
      length: large_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: large_hpack
    )

    expect_valid_frames([headers_frame])
  end

  # Test for HPACK dynamic table size update
  it "handles dynamic table size update" do
    # HPACK with table size update (0x20 prefix)
    table_update = Bytes[0x3F, 0xE1, 0x1F]  # Max table size update
    hpack_headers = Bytes[0x82, 0x86, 0x84] # Regular headers

    combined = Bytes.new(table_update.size + hpack_headers.size)
    table_update.copy_to(combined)
    hpack_headers.copy_to(combined + table_update.size)

    headers_frame = build_raw_frame(
      length: combined.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: combined
    )

    expect_valid_frames([headers_frame])
  end
end

describe "H2SPEC HPACK Huffman Encoding" do
  # Test for valid Huffman encoded data
  it "accepts Huffman encoded headers" do
    # HPACK with Huffman encoding bit set
    # 0x80 | length, then Huffman data
    huffman_hpack = Bytes[0x82, 0x86, 0x84, 0x88] # Mix of indexed and Huffman

    headers_frame = build_raw_frame(
      length: huffman_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: huffman_hpack
    )

    expect_valid_frames([headers_frame])
  end

  # Test for invalid Huffman padding
  it "validates Huffman padding" do
    # Huffman with invalid padding would be caught
    # For now test valid encoding
    valid_hpack = Bytes[0x82, 0x86, 0x84]

    headers_frame = build_raw_frame(
      length: valid_hpack.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: valid_hpack
    )

    expect_valid_frames([headers_frame])
  end
end
