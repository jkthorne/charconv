require "./spec_helper"

describe CharConv::Converter do
  describe "ASCII↔ASCII" do
    it "converts empty input" do
      c = CharConv::Converter.new("ASCII", "ASCII")
      result = c.convert(Bytes.empty)
      result.size.should eq(0)
    end

    it "converts hello world" do
      c = CharConv::Converter.new("ASCII", "ASCII")
      input = "hello world".to_slice
      result = c.convert(input)
      result.should eq(input)
    end

    it "stops at byte 0x80" do
      c = CharConv::Converter.new("ASCII", "ASCII")
      input = Bytes[0x48, 0x69, 0x80, 0x41] # "Hi" + 0x80 + "A"
      dst = Bytes.new(4)
      consumed, written = c.convert(input, dst)
      consumed.should eq(2)
      written.should eq(2)
    end
  end

  describe "UTF-8→ISO-8859-1" do
    it "passes through ASCII" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      result = c.convert("Hello World!".to_slice)
      result.should eq("Hello World!".to_slice)
    end

    it "converts café (é = U+00E9 → 0xE9)" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      result = c.convert("café".to_slice)
      result.should eq(Bytes[99, 97, 102, 0xE9])
    end

    it "converts ü (U+00FC → 0xFC)" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      result = c.convert("ü".to_slice)
      result.should eq(Bytes[0xFC])
    end

    it "converts £ (U+00A3 → 0xA3)" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      result = c.convert("£".to_slice)
      result.should eq(Bytes[0xA3])
    end

    it "fails on U+0100 (outside ISO-8859-1 range)" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      input = Bytes[0xC4, 0x80] # U+0100 in UTF-8
      expect_raises(CharConv::ConversionError) do
        c.convert(input)
      end
    end

    it "fails on truncated UTF-8 sequence" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      input = Bytes[0xC3] # incomplete 2-byte sequence
      dst = Bytes.new(4)
      consumed, written = c.convert(input, dst)
      consumed.should eq(0) # TOOFEW — nothing consumed
      written.should eq(0)
    end
  end

  describe "ISO-8859-1→UTF-8" do
    it "passes through ASCII" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      result = c.convert("Hello".to_slice)
      result.should eq("Hello".to_slice)
    end

    it "converts 0xE9 → U+00E9 (é in UTF-8: 0xC3 0xA9)" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      result = c.convert(Bytes[0xE9])
      result.should eq(Bytes[0xC3, 0xA9])
    end

    it "converts 0xFF → U+00FF (ÿ in UTF-8: 0xC3 0xBF)" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      result = c.convert(Bytes[0xFF])
      result.should eq(Bytes[0xC3, 0xBF])
    end

    it "converts all 256 byte values successfully" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      input = Bytes.new(256) { |i| i.to_u8 }
      result = c.convert(input)
      # Verify: first 128 bytes are identical (ASCII)
      result[0, 128].should eq(input[0, 128])
      # Bytes 128-255 each become 2-byte UTF-8 sequences
      result.size.should eq(128 + 128 * 2)
    end
  end

  describe "UTF-8→UTF-8" do
    it "passes through valid UTF-8" do
      c = CharConv::Converter.new("UTF-8", "UTF-8")
      input = "Hello 世界! 🌍".to_slice
      result = c.convert(input)
      result.should eq(input)
    end

    it "stops on invalid UTF-8" do
      c = CharConv::Converter.new("UTF-8", "UTF-8")
      input = Bytes[0x48, 0x69, 0xFF, 0x41] # "Hi" + invalid + "A"
      dst = Bytes.new(10)
      consumed, written = c.convert(input, dst)
      consumed.should eq(2) # stops at 0xFF
      written.should eq(2)
    end
  end

  describe "buffer boundaries" do
    it "handles exact fit" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      input = "abc".to_slice
      dst = Bytes.new(3) # exact size
      consumed, written = c.convert(input, dst)
      consumed.should eq(3)
      written.should eq(3)
    end

    it "handles output 1 byte short" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      # 0xE9 needs 2 bytes in UTF-8; give only 1 byte of output space
      input = Bytes[0xE9]
      dst = Bytes.new(1)
      consumed, written = c.convert(input, dst)
      consumed.should eq(0)
      written.should eq(0)
    end

    it "exercises 8-byte ASCII scanner on large input" do
      c = CharConv::Converter.new("ASCII", "ASCII")
      input = Bytes.new(1024, 0x41_u8) # 1KB of 'A'
      result = c.convert(input)
      result.should eq(input)
    end

    it "handles mixed ASCII and non-ASCII across word boundaries" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      # 7 ASCII bytes then a 2-byte UTF-8 char, repeated
      input = ("1234567é" * 10).to_slice
      result = c.convert(input)
      pattern = Bytes[0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0xE9]
      expected = Bytes.new(pattern.size * 10) { |i| pattern[i % pattern.size] }
      result.should eq(expected)
    end
  end

  describe "error cases" do
    it "raises ArgumentError for unknown source encoding" do
      expect_raises(ArgumentError, "Unknown encoding: EBCDIC") do
        CharConv::Converter.new("EBCDIC", "UTF-8")
      end
    end

    it "raises ArgumentError for unknown target encoding" do
      expect_raises(ArgumentError, "Unknown encoding: FAKE_ENCODING_XYZ") do
        CharConv::Converter.new("UTF-8", "FAKE_ENCODING_XYZ")
      end
    end
  end

  describe "convert_with_status" do
    it "returns OK when all input consumed" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      src = "Hello".to_slice
      dst = Bytes.new(16)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::OK
      consumed.should eq 5
      written.should eq 5
    end

    it "returns E2BIG when output buffer is full" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      src = Bytes[0xE9] # é → 2-byte UTF-8, but only 1 byte output
      dst = Bytes.new(1)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::E2BIG
      consumed.should eq 0
      written.should eq 0
    end

    it "returns E2BIG when ASCII copy exceeds output" do
      c = CharConv::Converter.new("ASCII", "ASCII")
      src = "Hello World".to_slice
      dst = Bytes.new(5) # only room for 5 bytes
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::E2BIG
      consumed.should eq 5
      written.should eq 5
    end

    it "returns EILSEQ on invalid byte" do
      c = CharConv::Converter.new("UTF-8", "UTF-8")
      src = Bytes[0x48, 0x69, 0xFF] # "Hi" + invalid
      dst = Bytes.new(16)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::EILSEQ
      consumed.should eq 2
      written.should eq 2
    end

    it "returns EINVAL on incomplete sequence" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      src = Bytes[0xC3] # incomplete 2-byte UTF-8
      dst = Bytes.new(16)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::EINVAL
      consumed.should eq 0
      written.should eq 0
    end

    it "returns EILSEQ on unencodable codepoint" do
      c = CharConv::Converter.new("UTF-8", "ASCII")
      src = "café".to_slice # é not encodable in ASCII
      dst = Bytes.new(16)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::EILSEQ
      consumed.should eq 3 # "caf" consumed, stopped at é
      written.should eq 3
    end

    it "returns OK with IGNORE flag on invalid bytes" do
      c = CharConv::Converter.new("UTF-8", "ASCII//IGNORE")
      src = "café".to_slice
      dst = Bytes.new(16)
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::OK
      consumed.should eq src.size
      written.should eq 3 # "caf"
      dst[0, written].should eq "caf".to_slice
    end

    it "returns OK on empty input" do
      c = CharConv::Converter.new("UTF-8", "UTF-8")
      consumed, written, status = c.convert_with_status(Bytes.empty, Bytes.new(16))
      status.should eq CharConv::ConvertStatus::OK
      consumed.should eq 0
      written.should eq 0
    end

    it "returns correct status for non-ASCII-superset (general path)" do
      c = CharConv::Converter.new("UTF-8", "UTF-16BE")
      src = "Hi".to_slice
      dst = Bytes.new(2) # only room for 1 UTF-16 char
      consumed, written, status = c.convert_with_status(src, dst)
      status.should eq CharConv::ConvertStatus::E2BIG
      consumed.should eq 1
      written.should eq 2
    end
  end

  describe "one-shot API" do
    it "returns correct Bytes for UTF-8 to ISO-8859-1" do
      c = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      result = c.convert("café résumé".to_slice)
      # c a f é   r é s u m é
      expected = Bytes[99, 97, 102, 0xE9, 32, 114, 0xE9, 115, 117, 109, 0xE9]
      result.should eq(expected)
    end

    it "returns correct Bytes for ISO-8859-1 to UTF-8" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      input = Bytes[0xA9] # © in ISO-8859-1
      result = c.convert(input)
      result.should eq(Bytes[0xC2, 0xA9])
    end
  end

  describe "#dup" do
    it "produces an independent converter" do
      c1 = CharConv::Converter.new("UTF-8", "ISO-8859-1")
      c2 = c1.dup
      # Convert with c1
      r1 = c1.convert("café".to_slice)
      r1.should eq(Bytes[99, 97, 102, 0xE9])
      # c2 should be unaffected and convert independently
      r2 = c2.convert("über".to_slice)
      r2.should eq(Bytes[0xFC, 98, 101, 114])
    end

    it "handles stateful encodings (ISO-2022-JP)" do
      c1 = CharConv::Converter.new("UTF-8", "ISO-2022-JP")
      c2 = c1.dup
      # Both should produce correct output independently
      r1 = c1.convert("A".to_slice)
      r2 = c2.convert("A".to_slice)
      r1.should eq(r2)
    end

    it "dup'd converter has fresh state for ISO-2022-JP decode" do
      c1 = CharConv::Converter.new("ISO-2022-JP", "UTF-8")
      # Convert some Japanese to change c1's internal state
      # ESC $ B (switch to JIS X 0208) + 0x24 0x22 (あ)
      jp_input = Bytes[0x1B, 0x24, 0x42, 0x24, 0x22]
      dst = Bytes.new(64)
      c1.convert(jp_input, dst)
      # Now dup — should get a fresh converter in ASCII mode
      c2 = c1.dup
      r = c2.convert("Hello".to_slice)
      String.new(r).should eq("Hello")
    end
  end

  describe "one-shot allocation cap" do
    it "normal conversions still work" do
      c = CharConv::Converter.new("ISO-8859-1", "UTF-8")
      input = Bytes.new(256) { |i| i.to_u8 }
      result = c.convert(input)
      result.size.should eq(128 + 128 * 2) # 128 ASCII + 128 × 2-byte UTF-8
    end

    it "grow-and-retry works for expanding conversions" do
      # C99 encoding: every non-ASCII codepoint → \uXXXX (6 chars)
      # "é" (2 UTF-8 bytes) → \u00E9 (6 bytes). 50 é's = 100 bytes in, 300 bytes out.
      # Initial buffer = 100*2 = 200, too small → retry with 400.
      c = CharConv::Converter.new("UTF-8", "C99")
      input = ("é" * 50).to_slice
      result = c.convert(input)
      result.size.should eq(300)
    end

    it "stateful encoding (ISO-2022-JP) correct after retry" do
      c = CharConv::Converter.new("UTF-8", "ISO-2022-JP")
      # Simple ASCII — should work fine
      result = c.convert("Hello".to_slice)
      String.new(result).should eq("Hello")
    end
  end
end
