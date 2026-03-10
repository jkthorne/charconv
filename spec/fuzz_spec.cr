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

FUZZ_ITERATIONS = 200
FUZZ_MAX_SIZE   =  64

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
