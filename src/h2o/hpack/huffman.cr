module H2O::HPACK
  module Huffman
    HUFFMAN_CODES = [
      {0x1ff8_u32, 13}, {0x7fffd8_u32, 23}, {0xfffffe2_u32, 28}, {0xfffffe3_u32, 28}, {0xfffffe4_u32, 28}, {0xfffffe5_u32, 28}, {0xfffffe6_u32, 28}, {0xfffffe7_u32, 28},
      {0xfffffe8_u32, 28}, {0xffffea_u32, 24}, {0x3ffffffc_u32, 30}, {0xfffffe9_u32, 28}, {0xfffffea_u32, 28}, {0x3ffffffd_u32, 30}, {0xfffffeb_u32, 28}, {0xfffffec_u32, 28},
      {0xfffffed_u32, 28}, {0xfffffee_u32, 28}, {0xfffffef_u32, 28}, {0xffffff0_u32, 28}, {0xffffff1_u32, 28}, {0xffffff2_u32, 28}, {0x3ffffffe_u32, 30}, {0xffffff3_u32, 28},
      {0xffffff4_u32, 28}, {0xffffff5_u32, 28}, {0xffffff6_u32, 28}, {0xffffff7_u32, 28}, {0xffffff8_u32, 28}, {0xffffff9_u32, 28}, {0xffffffa_u32, 28}, {0xffffffb_u32, 28},
      {0x14_u32, 6}, {0x3f8_u32, 10}, {0x3f9_u32, 10}, {0xffa_u32, 12}, {0x1ff9_u32, 13}, {0x15_u32, 6}, {0xf8_u32, 8}, {0x7fa_u32, 11},
      {0x3fa_u32, 10}, {0x3fb_u32, 10}, {0xf9_u32, 8}, {0x7fb_u32, 11}, {0xfa_u32, 8}, {0x16_u32, 6}, {0x17_u32, 6}, {0x18_u32, 6},
      {0x0_u32, 5}, {0x1_u32, 5}, {0x2_u32, 5}, {0x19_u32, 6}, {0x1a_u32, 6}, {0x1b_u32, 6}, {0x1c_u32, 6}, {0x1d_u32, 6},
      {0x1e_u32, 6}, {0x1f_u32, 6}, {0x5c_u32, 7}, {0xfb_u32, 8}, {0x7ffc_u32, 15}, {0x20_u32, 6}, {0xffb_u32, 12}, {0x3fc_u32, 10},
      {0x1ffa_u32, 13}, {0x21_u32, 6}, {0x5d_u32, 7}, {0x5e_u32, 7}, {0x5f_u32, 7}, {0x60_u32, 7}, {0x61_u32, 7}, {0x62_u32, 7},
      {0x63_u32, 7}, {0x64_u32, 7}, {0x65_u32, 7}, {0x66_u32, 7}, {0x67_u32, 7}, {0x68_u32, 7}, {0x69_u32, 7}, {0x6a_u32, 7},
      {0x6b_u32, 7}, {0x6c_u32, 7}, {0x6d_u32, 7}, {0x6e_u32, 7}, {0x6f_u32, 7}, {0x70_u32, 7}, {0x71_u32, 7}, {0x72_u32, 7},
      {0xfc_u32, 8}, {0x73_u32, 7}, {0xfd_u32, 8}, {0x1ffb_u32, 13}, {0x7fff0_u32, 19}, {0x1ffc_u32, 13}, {0x3ffc_u32, 14}, {0x22_u32, 6},
      {0x7ffd_u32, 15}, {0x3_u32, 5}, {0x23_u32, 6}, {0x4_u32, 5}, {0x24_u32, 6}, {0x5_u32, 5}, {0x25_u32, 6}, {0x26_u32, 6},
      {0x27_u32, 6}, {0x6_u32, 5}, {0x74_u32, 7}, {0x75_u32, 7}, {0x28_u32, 6}, {0x29_u32, 6}, {0x2a_u32, 6}, {0x7_u32, 5},
      {0x2b_u32, 6}, {0x76_u32, 7}, {0x2c_u32, 6}, {0x8_u32, 5}, {0x9_u32, 5}, {0x2d_u32, 6}, {0x77_u32, 7}, {0x78_u32, 7},
      {0x79_u32, 7}, {0x7a_u32, 7}, {0x7b_u32, 7}, {0x7ffe_u32, 15}, {0x7fc_u32, 11}, {0x3ffd_u32, 14}, {0x1ffd_u32, 13}, {0xffffffc_u32, 28},
      {0xfffe6_u32, 20}, {0x3fffd2_u32, 22}, {0xfffe7_u32, 20}, {0xfffe8_u32, 20}, {0x3fffd3_u32, 22}, {0x3fffd4_u32, 22}, {0x3fffd5_u32, 22}, {0x7fffd9_u32, 23},
      {0x3fffd6_u32, 22}, {0x7fffda_u32, 23}, {0x7fffdb_u32, 23}, {0x7fffdc_u32, 23}, {0x7fffdd_u32, 23}, {0x7fffde_u32, 23}, {0xffffeb_u32, 24}, {0x7fffdf_u32, 23},
      {0xffffec_u32, 24}, {0xffffed_u32, 24}, {0x3fffd7_u32, 22}, {0x7fffe0_u32, 23}, {0xffffee_u32, 24}, {0x7fffe1_u32, 23}, {0x7fffe2_u32, 23}, {0x7fffe3_u32, 23},
      {0x7fffe4_u32, 23}, {0x1fffdc_u32, 21}, {0x3fffd8_u32, 22}, {0x7fffe5_u32, 23}, {0x3fffd9_u32, 22}, {0x7fffe6_u32, 23}, {0x7fffe7_u32, 23}, {0xffffef_u32, 24},
      {0x3fffda_u32, 22}, {0x1fffdd_u32, 21}, {0xfffe9_u32, 20}, {0x3fffdb_u32, 22}, {0x3fffdc_u32, 22}, {0x7fffe8_u32, 23}, {0x7fffe9_u32, 23}, {0x1fffde_u32, 21},
      {0x7fffea_u32, 23}, {0x3fffdd_u32, 22}, {0x3fffde_u32, 22}, {0xfffff0_u32, 24}, {0x1fffdf_u32, 21}, {0x3fffdf_u32, 22}, {0x7fffeb_u32, 23}, {0x7fffec_u32, 23},
      {0x1fffe0_u32, 21}, {0x1fffe1_u32, 21}, {0x3fffe0_u32, 22}, {0x1fffe2_u32, 21}, {0x7fffed_u32, 23}, {0x3fffe1_u32, 22}, {0x7fffee_u32, 23}, {0x7fffef_u32, 23},
      {0xfffea_u32, 20}, {0x3fffe2_u32, 22}, {0x3fffe3_u32, 22}, {0x3fffe4_u32, 22}, {0x7ffff0_u32, 23}, {0x3fffe5_u32, 22}, {0x3fffe6_u32, 22}, {0x7ffff1_u32, 23},
      {0x3ffffe0_u32, 26}, {0x3ffffe1_u32, 26}, {0xfffeb_u32, 20}, {0x7fff1_u32, 19}, {0x3fffe7_u32, 22}, {0x7ffff2_u32, 23}, {0x3fffe8_u32, 22}, {0x1ffffec_u32, 25},
      {0x3ffffe2_u32, 26}, {0x3ffffe3_u32, 26}, {0x3ffffe4_u32, 26}, {0x7ffffde_u32, 27}, {0x7ffffdf_u32, 27}, {0x3ffffe5_u32, 26}, {0xfffff1_u32, 24}, {0x1ffffed_u32, 25},
      {0x7fff2_u32, 19}, {0x1fffe3_u32, 21}, {0x3ffffe6_u32, 26}, {0x7ffffe0_u32, 27}, {0x7ffffe1_u32, 27}, {0x3ffffe7_u32, 26}, {0x7ffffe2_u32, 27}, {0xfffff2_u32, 24},
      {0x1fffe4_u32, 21}, {0x1fffe5_u32, 21}, {0x3ffffe8_u32, 26}, {0x3ffffe9_u32, 26}, {0xffffffd_u32, 28}, {0x7ffffe3_u32, 27}, {0x7ffffe4_u32, 27}, {0x7ffffe5_u32, 27},
      {0xfffec_u32, 20}, {0xfffff3_u32, 24}, {0xfffed_u32, 20}, {0x1fffe6_u32, 21}, {0x3fffe9_u32, 22}, {0x1fffe7_u32, 21}, {0x1fffe8_u32, 21}, {0x7ffff3_u32, 23},
      {0x3fffea_u32, 22}, {0x3fffeb_u32, 22}, {0x1ffffee_u32, 25}, {0x1ffffef_u32, 25}, {0xfffff4_u32, 24}, {0xfffff5_u32, 24}, {0x3ffffea_u32, 26}, {0x7ffff4_u32, 23},
      {0x3ffffeb_u32, 26}, {0x7ffffe6_u32, 27}, {0x3ffffec_u32, 26}, {0x3ffffed_u32, 26}, {0x7ffffe7_u32, 27}, {0x7ffffe8_u32, 27}, {0x7ffffe9_u32, 27}, {0x7ffffea_u32, 27},
      {0x7ffffeb_u32, 27}, {0xffffffe_u32, 28}, {0x7ffffec_u32, 27}, {0x7ffffed_u32, 27}, {0x7ffffee_u32, 27}, {0x7ffffef_u32, 27}, {0x7fffff0_u32, 27}, {0x3ffffee_u32, 26},
      {0x3fffffff_u32, 30},
    ]

    EOS_SYMBOL = 256

    # Pre-computed decode lookup table for O(1) symbol lookup
    private DECODE_LOOKUP = build_decode_lookup

    private def self.build_decode_lookup : Hash(UInt32, {Int32, Int32})
      lookup = Hash(UInt32, {Int32, Int32}).new
      HUFFMAN_CODES.each_with_index do |(code, length), symbol|
        lookup[code] = {symbol, length}
      end
      lookup
    end

    def self.encode(data : String) : Bytes
      BufferPool.with_frame_buffer(data.bytesize * 2) do |buffer|
        bits = 0_u64
        bit_count = 0
        output_pos = 0

        data.each_byte do |byte|
          code, length = HUFFMAN_CODES[byte]
          bits = (bits << length) | code.to_u64
          bit_count += length

          while bit_count >= 8
            bit_count -= 8
            buffer[output_pos] = (bits >> bit_count).to_u8
            output_pos += 1
            bits &= (1_u64 << bit_count) - 1
          end
        end

        if bit_count > 0
          padding = 8 - bit_count
          bits = (bits << padding) | ((1_u64 << padding) - 1)
          buffer[output_pos] = bits.to_u8
          output_pos += 1
        end

        result = Bytes.new(output_pos)
        result.copy_from(buffer[0, output_pos])
        result
      end
    end

    def self.decode(data : Bytes, max_decoded_length : Int32 = 8192) : String
      # Pre-check: Huffman can expand by at most 8/5 ratio
      max_possible_expansion = (data.size * 8) // 5 + 1
      if max_possible_expansion > max_decoded_length
        raise CompressionError.new("Huffman decoded length would exceed limit: #{max_possible_expansion} > #{max_decoded_length}")
      end

      String.build do |result|
        bits = 0_u32
        bit_count = 0
        decoded_length = 0

        data.each do |byte|
          bits = (bits << 8) | byte.to_u32
          bit_count += 8

          while bit_count >= 5
            symbol, consumed_bits = decode_symbol(bits, bit_count)
            break if symbol.nil?

            if symbol == EOS_SYMBOL
              raise CompressionError.new("Unexpected EOS symbol in Huffman data")
            end

            # Check decoded length limit
            decoded_length += 1
            if decoded_length > max_decoded_length
              raise CompressionError.new("Huffman decoded length exceeds limit: #{decoded_length} > #{max_decoded_length}")
            end

            result << symbol.chr
            bits &= (1_u32 << (bit_count - consumed_bits)) - 1
            bit_count -= consumed_bits
          end
        end

        if bit_count > 0
          padding = (1_u32 << bit_count) - 1
          if bits != padding
            raise CompressionError.new("Invalid Huffman padding")
          end
        end
      end
    end

    private def self.decode_symbol(bits : UInt32, bit_count : Int32) : {Int32?, Int32}
      return {nil, 0} if bit_count < 5

      (30.downto(5)).each do |length|
        next if bit_count < length

        mask = (1_u32 << length) - 1
        code = (bits >> (bit_count - length)) & mask

        if symbol_length = DECODE_LOOKUP[code]?
          symbol, actual_length = symbol_length
          return {symbol, actual_length} if actual_length == length
        end
      end

      {nil, 0}
    end

    private def self.symbol_length(symbol : Int32) : Int32
      return 30 if symbol == EOS_SYMBOL
      HUFFMAN_CODES[symbol][1]
    end
  end
end
