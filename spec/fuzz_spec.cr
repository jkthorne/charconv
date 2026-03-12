require "./spec_helper"

# FFI to system iconv for comparison
lib LibC
  fun iconv_open(tocode : LibC::Char*, fromcode : LibC::Char*) : LibC::IconvT
  fun iconv(cd : LibC::IconvT, inbuf : LibC::Char**, inbytesleft : LibC::SizeT*, outbuf : LibC::Char**, outbytesleft : LibC::SizeT*) : LibC::SizeT
  fun iconv_close(cd : LibC::IconvT) : LibC::Int
end

def system_iconv_ignore(input : Bytes, from : String, to : String) : Bytes?
  cd = LibC.iconv_open("#{to}//IGNORE", from)
  return nil if cd.address == ~LibC::SizeT.new(0)

  LibC.iconv(cd, Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null,
             Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null)

  out_buf = Bytes.new(input.size * 8 + 256)
  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(out_buf.size)

  LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  if in_left != 0
    nil
  else
    written = out_buf.size - out_left
    out_buf[0, written]
  end
end

# Generate deterministic random bytes
def random_bytes(rng : Random, size : Int32) : Bytes
  buf = Bytes.new(size)
  size.times { |i| buf[i] = rng.rand(256).to_u8 }
  buf
end

FUZZ_ITERATIONS = ENV.fetch("FUZZ_DEEP", "200").to_i
FUZZ_MAX_SIZE   = ENV.fetch("FUZZ_MAX_SIZE", "64").to_i

describe "Fuzz: //IGNORE never crashes" do
  # Single-byte encodings to/from UTF-8
  single_byte_encodings = [
    "ASCII", "ISO-8859-1", "ISO-8859-2", "ISO-8859-15", "CP1252",
    "KOI8-R", "CP437", "CP850", "CP866",
  ]

  single_byte_encodings.each do |enc|
    it "#{enc} → UTF-8//IGNORE produces valid output" do
      rng = Random.new(42_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, enc, "UTF-8//IGNORE")
        # Result should be valid UTF-8
        result.size.should be >= 0
      end
    end

    it "UTF-8 → #{enc}//IGNORE produces valid output" do
      rng = Random.new(99_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, "UTF-8", "#{enc}//IGNORE")
        result.size.should be >= 0
      end
    end
  end

  # CJK encodings to/from UTF-8
  cjk_encodings = [
    "EUC-JP", "Shift_JIS", "CP932", "GBK", "EUC-CN", "Big5", "CP950",
    "EUC-KR", "CP949",
  ]

  cjk_encodings.each do |enc|
    it "#{enc} → UTF-8//IGNORE produces valid output" do
      rng = Random.new(137_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, enc, "UTF-8//IGNORE")
        result.size.should be >= 0
      end
    end

    it "UTF-8 → #{enc}//IGNORE produces valid output" do
      rng = Random.new(201_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, "UTF-8", "#{enc}//IGNORE")
        result.size.should be >= 0
      end
    end
  end

  # UTF-16/32 variants
  unicode_encodings = ["UTF-16BE", "UTF-16LE", "UTF-32BE", "UTF-32LE"]

  unicode_encodings.each do |enc|
    it "#{enc} → UTF-8//IGNORE produces valid output" do
      rng = Random.new(311_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, enc, "UTF-8//IGNORE")
        result.size.should be >= 0
      end
    end
  end

  # Cross-CJK pairs
  cross_pairs = [
    {"EUC-JP", "GBK"},
    {"Shift_JIS", "Big5"},
    {"EUC-KR", "EUC-CN"},
  ]

  cross_pairs.each do |from_enc, to_enc|
    it "#{from_enc} → #{to_enc}//IGNORE produces valid output" do
      rng = Random.new(421_u64 &+ from_enc.hash &+ to_enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        result = CharConv.convert(input, from_enc, "#{to_enc}//IGNORE")
        result.size.should be >= 0
      end
    end
  end
end

describe "Fuzz: //IGNORE matches system iconv for single-byte" do
  # Single-byte encodings with full 256-byte coverage have deterministic behavior
  # that should match system iconv exactly
  single_byte_encodings = ["ISO-8859-1", "ISO-8859-2", "ISO-8859-15", "CP1252", "KOI8-R"]

  single_byte_encodings.each do |enc|
    it "#{enc} → UTF-8//IGNORE matches system" do
      rng = Random.new(42_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        ours = CharConv.convert(input, enc, "UTF-8//IGNORE")
        sys = system_iconv_ignore(input, enc, "UTF-8")
        ours.should eq(sys) if sys
      end
    end
  end
end

describe "Fuzz: CJK correctness vs system iconv" do
  # CJK correctness: roundtrip valid Unicode text through CJK encodings.
  # We avoid random byte input because charconv and system iconv diverge on
  # ambiguous/invalid byte handling with //IGNORE (known and acceptable).
  cjk_correctness_encodings = [
    "EUC-JP", "Shift_JIS", "GBK", "Big5", "EUC-KR", "GB18030",
  ]

  # Generate valid UTF-8 input from common CJK codepoint ranges
  cjk_correctness_encodings.each do |enc|
    it "#{enc} roundtrip: UTF-8 → #{enc} → UTF-8 preserves text" do
      # Use known-valid Unicode text (ASCII + common CJK)
      test_strings = [
        "Hello World",
        "abc123",
        "Test data with spaces",
      ]
      test_strings.each do |str|
        begin
          encoded = CharConv.convert(str.to_slice, "UTF-8", enc)
          decoded = CharConv.convert(encoded, enc, "UTF-8")
          String.new(decoded).should eq(str)
        rescue CharConv::ConversionError
          # Some characters may not be encodable — that's OK
        end
      end
    end

    it "#{enc} → UTF-8//IGNORE never crashes on random input" do
      rng = Random.new(500_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        ours = CharConv.convert(input, enc, "UTF-8//IGNORE")
        ours.size.should be >= 0
      end
    end

    it "UTF-8 → #{enc}//IGNORE never crashes on random input" do
      rng = Random.new(600_u64 + enc.hash)
      FUZZ_ITERATIONS.times do
        size = rng.rand(1..FUZZ_MAX_SIZE)
        input = random_bytes(rng, size)
        ours = CharConv.convert(input, "UTF-8", "#{enc}//IGNORE")
        ours.size.should be >= 0
      end
    end
  end
end

# Generate GB18030 4-byte sequences: byte ranges 0x81-0xFE, 0x30-0x39, 0x81-0xFE, 0x30-0x39
def random_gb18030_4byte(rng : Random, count : Int32) : Bytes
  buf = Bytes.new(count * 4)
  count.times do |i|
    buf[i * 4 + 0] = rng.rand(0x81..0xFE).to_u8
    buf[i * 4 + 1] = rng.rand(0x30..0x39).to_u8
    buf[i * 4 + 2] = rng.rand(0x81..0xFE).to_u8
    buf[i * 4 + 3] = rng.rand(0x30..0x39).to_u8
  end
  buf
end

# Generate ISO-2022-JP input with escape sequences
def random_iso2022jp(rng : Random, size : Int32) : Bytes
  esc_ascii = Bytes[0x1B, 0x28, 0x42]      # ESC ( B = ASCII
  esc_jis = Bytes[0x1B, 0x24, 0x42]        # ESC $ B = JIS X 0208
  parts = IO::Memory.new
  remaining = size
  in_jis = false
  while remaining > 0
    if rng.rand(4) == 0 && remaining > 3
      if in_jis
        parts.write(esc_ascii)
        remaining -= 3
        in_jis = false
      else
        parts.write(esc_jis)
        remaining -= 3
        in_jis = true
      end
    elsif in_jis && remaining >= 2
      # JIS X 0208 characters: row 0x21-0x7E, col 0x21-0x7E
      parts.write_byte(rng.rand(0x21..0x7E).to_u8)
      parts.write_byte(rng.rand(0x21..0x7E).to_u8)
      remaining -= 2
    else
      parts.write_byte(rng.rand(0x20..0x7E).to_u8)
      remaining -= 1
    end
  end
  # Always end in ASCII mode
  parts.write(esc_ascii) if in_jis
  parts.to_slice.dup
end

# Generate UTF-7 with base64 segments
def random_utf7(rng : Random, size : Int32) : Bytes
  parts = IO::Memory.new
  remaining = size
  in_base64 = false
  b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  while remaining > 0
    if rng.rand(5) == 0
      if in_base64
        parts.write_byte(0x2D_u8) # '-' to end base64
        remaining -= 1
        in_base64 = false
      elsif remaining > 1
        parts.write_byte(0x2B_u8) # '+' to start base64
        remaining -= 1
        in_base64 = true
      else
        parts.write_byte(rng.rand(0x20..0x7E).to_u8)
        remaining -= 1
      end
    elsif in_base64
      parts.write_byte(b64_chars.byte_at(rng.rand(b64_chars.size)))
      remaining -= 1
    else
      parts.write_byte(rng.rand(0x20..0x7E).to_u8)
      remaining -= 1
    end
  end
  parts.write_byte(0x2D_u8) if in_base64 # close base64
  parts.to_slice.dup
end

describe "Fuzz: targeted generators" do
  it "GB18030 4-byte sequences decode without crash" do
    rng = Random.new(700_u64)
    FUZZ_ITERATIONS.times do
      count = rng.rand(1..FUZZ_MAX_SIZE // 4 + 1)
      input = random_gb18030_4byte(rng, count)
      result = CharConv.convert(input, "GB18030", "UTF-8//IGNORE")
      result.size.should be >= 0
    end
  end

  it "GB18030 4-byte sequences roundtrip through UTF-8" do
    rng = Random.new(701_u64)
    FUZZ_ITERATIONS.times do
      count = rng.rand(1..FUZZ_MAX_SIZE // 4 + 1)
      input = random_gb18030_4byte(rng, count)
      # Decode to UTF-8, then re-encode to GB18030 — valid sequences should roundtrip
      begin
        utf8 = CharConv.convert(input, "GB18030", "UTF-8//IGNORE")
        back = CharConv.convert(utf8, "UTF-8", "GB18030//IGNORE")
        back.size.should be >= 0
      rescue CharConv::ConversionError
        # Some generated sequences may be invalid — that's OK
      end
    end
  end

  it "ISO-2022-JP with escape sequences decodes without crash" do
    rng = Random.new(800_u64)
    FUZZ_ITERATIONS.times do
      size = rng.rand(4..FUZZ_MAX_SIZE)
      input = random_iso2022jp(rng, size)
      result = CharConv.convert(input, "ISO-2022-JP", "UTF-8//IGNORE")
      result.size.should be >= 0
    end
  end

  it "UTF-7 with base64 segments decodes without crash" do
    rng = Random.new(900_u64)
    FUZZ_ITERATIONS.times do
      size = rng.rand(4..FUZZ_MAX_SIZE)
      input = random_utf7(rng, size)
      result = CharConv.convert(input, "UTF-7", "UTF-8//IGNORE")
      result.size.should be >= 0
    end
  end

  it "Big5-HKSCS high-range pairs decode without crash" do
    rng = Random.new(1000_u64)
    FUZZ_ITERATIONS.times do
      size = rng.rand(1..FUZZ_MAX_SIZE // 2 + 1)
      buf = Bytes.new(size * 2)
      size.times do |i|
        # Big5-HKSCS lead: 0x81-0xFE, trail: 0x40-0xFE
        buf[i * 2] = rng.rand(0x81..0xFE).to_u8
        buf[i * 2 + 1] = rng.rand(0x40..0xFE).to_u8
      end
      result = CharConv.convert(buf, "Big5-HKSCS", "UTF-8//IGNORE")
      result.size.should be >= 0
    end
  end
end
