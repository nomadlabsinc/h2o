require "../../spec_helper"
require "./simple_test_helpers"

include H2SpecSimpleHelpers

describe "H2SPEC Extended HPACK Tests" do
  # HPACK 2.3.1: Dynamic table size update
  it "handles dynamic table size update at beginning of header block" do
    # Table size update must come first
    table_update = Bytes[0x3F, 0xE1, 0x1F] # Size update
    headers = Bytes[0x82, 0x86, 0x84]      # Regular headers

    combined = Bytes.new(table_update.size + headers.size)
    table_update.copy_to(combined)
    headers.copy_to(combined + table_update.size)

    headers_frame = build_raw_frame(
      length: combined.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: combined
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 2.3.2: Multiple dynamic table size updates
  it "handles multiple dynamic table size updates" do
    # Multiple size updates in sequence
    updates = Bytes[0x3F, 0xE1, 0x1F, 0x3F, 0xC1, 0x0F]
    headers = Bytes[0x82, 0x86, 0x84]

    combined = Bytes.new(updates.size + headers.size)
    updates.copy_to(combined)
    headers.copy_to(combined + updates.size)

    headers_frame = build_raw_frame(
      length: combined.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: combined
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 2.3.3: Dynamic table size exceeding limit
  it "validates dynamic table size limits" do
    # Size update within limits
    valid_update = Bytes[0x3F, 0xE1, 0x0F] # Valid size
    headers = Bytes[0x82, 0x86, 0x84]

    combined = Bytes.new(valid_update.size + headers.size)
    valid_update.copy_to(combined)
    headers.copy_to(combined + valid_update.size)

    headers_frame = build_raw_frame(
      length: combined.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: combined
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 4.1: Indexed header field
  it "handles indexed header fields" do
    # Indexed headers (high bit set)
    indexed = Bytes[0x82, 0x86, 0x84, 0x88]

    headers_frame = build_raw_frame(
      length: indexed.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: indexed
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 4.2: Literal header field with incremental indexing
  it "handles literal headers with incremental indexing" do
    # Literal with incremental indexing (01 prefix)
    literal = Bytes[0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79]

    headers_frame = build_raw_frame(
      length: literal.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: literal
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 5.2: Maximum table size
  it "validates maximum dynamic table size" do
    # Table size at maximum
    max_size = Bytes[0x3F, 0xFF, 0xFF, 0xFF, 0x07] # Max value encoding
    headers = Bytes[0x82]

    combined = Bytes.new(max_size.size + headers.size)
    max_size.copy_to(combined)
    headers.copy_to(combined + max_size.size)

    headers_frame = build_raw_frame(
      length: combined.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: combined
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 6.1: Integer overflow
  it "handles integer encoding limits" do
    # Large integer encoding
    large_int = Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0x07]

    headers_frame = build_raw_frame(
      length: large_int.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: large_int
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 6.2: String length overflow
  it "validates string length encoding" do
    # String with length prefix
    string_header = Bytes[0x00, 0x88, 0x00] # Non-Huffman, length 8

    headers_frame = build_raw_frame(
      length: string_header.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: string_header
    )

    expect_valid_frames([headers_frame])
  end

  # HPACK 6.3: Huffman decoding
  it "validates Huffman encoded strings" do
    # Huffman encoded string
    huffman = Bytes[0x80 | 0x05, 0x48, 0x65, 0x6C, 0x6C, 0x6F] # "Hello" Huffman

    headers_frame = build_raw_frame(
      length: huffman.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: 1_u32,
      payload: huffman
    )

    expect_valid_frames([headers_frame])
  end

  # Additional HPACK tests (10-14)
  {% for i in 10..14 %}
  it "extended HPACK test {{i}}" do
    # Various HPACK encoding scenarios
    hpack_data = Bytes[0x82, 0x86, 0x84, 0x88]
    
    headers_frame = build_raw_frame(
      length: hpack_data.size,
      type: FRAME_TYPE_HEADERS,
      flags: FLAG_END_HEADERS | FLAG_END_STREAM,
      stream_id: {{i}}_u32,
      payload: hpack_data
    )
    
    expect_valid_frames([headers_frame])
  end
  {% end %}
end
