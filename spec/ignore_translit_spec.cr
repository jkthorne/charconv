require "./spec_helper"

# FFI to system iconv for comparison
lib LibC
  fun iconv_open(tocode : LibC::Char*, fromcode : LibC::Char*) : LibC::IconvT
  fun iconv(cd : LibC::IconvT, inbuf : LibC::Char**, inbytesleft : LibC::SizeT*, outbuf : LibC::Char**, outbytesleft : LibC::SizeT*) : LibC::SizeT
  fun iconv_close(cd : LibC::IconvT) : LibC::Int
end

def system_iconv(input : Bytes, from : String, to : String) : Bytes?
  cd = LibC.iconv_open(to, from)
  return nil if cd.address == ~LibC::SizeT.new(0)

  LibC.iconv(cd, Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null,
             Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null)

  out_buf = Bytes.new(input.size * 8 + 256)
  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(out_buf.size)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  # For //IGNORE, iconv may return non-zero (number of irreversible conversions)
  # but still succeed (in_left == 0). For //TRANSLIT, same thing.
  if in_left != 0
    nil
  else
    written = out_buf.size - out_left
    out_buf[0, written]
  end
end

describe "//IGNORE" do
  it "skips invalid UTF-8 bytes when decoding" do
    # Mix of valid UTF-8 and invalid bytes
    # "A" + 0xFF (invalid) + "B" + 0xFE (invalid) + "C"
    input = Bytes[0x41, 0xFF, 0x42, 0xFE, 0x43]
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    String.new(result).should eq("ABC")
  end

  it "drops unencodable characters" do
    # UTF-8 "Héllo" — é (U+00E9) can't be encoded in ASCII
    input = "Héllo".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    String.new(result).should eq("Hllo")
  end

  it "handles all-invalid input" do
    input = Bytes[0xFF, 0xFE, 0xFD]
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    result.size.should eq(0)
  end

  it "handles empty input" do
    input = Bytes.empty
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    result.size.should eq(0)
  end

  it "passes through valid conversions unchanged" do
    input = "Hello World".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    String.new(result).should eq("Hello World")
  end

  it "skips invalid bytes in CJK decode" do
    # Valid EUC-JP "日" (0xC6FC) + invalid 0x80 + valid ASCII "A"
    input = Bytes[0xC6, 0xFC, 0x80, 0x41]
    result = CharConv.convert(input, "EUC-JP", "UTF-8//IGNORE")
    # Should get "日A" — the 0x80 byte is skipped
    result.should eq("日A".to_slice)
  end

  it "drops unencodable chars when encoding to single-byte" do
    # "café" in UTF-8 → ISO-8859-1 can handle it, but ASCII can't handle é
    input = "café".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    String.new(result).should eq("caf")
  end

  it "matches system iconv for UTF-8 to ASCII//IGNORE" do
    input = "Héllo wörld".to_slice
    ours = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
    sys = system_iconv(input, "UTF-8", "ASCII//IGNORE")
    ours.should eq(sys) if sys
  end

  it "matches system iconv for invalid UTF-8 to UTF-8//IGNORE" do
    input = Bytes[0x48, 0x65, 0xFF, 0x6C, 0x6C, 0xFE, 0x6F]
    ours = CharConv.convert(input, "UTF-8", "UTF-8//IGNORE")
    sys = system_iconv(input, "UTF-8", "UTF-8//IGNORE")
    ours.should eq(sys) if sys
  end
end

describe "//TRANSLIT" do
  it "transliterates accented characters" do
    input = "café résumé".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("cafe resume")
  end

  it "transliterates ligatures" do
    input = "Æthelred".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("AEthelred")
  end

  it "transliterates curly quotes" do
    input = "\u{201C}hello\u{201D}".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("\"hello\"")
  end

  it "transliterates dashes" do
    input = "foo\u{2014}bar".to_slice # em dash
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("foo--bar")
  end

  it "transliterates symbols" do
    input = "\u{00A9}2024".to_slice # ©2024
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("(c)2024")
  end

  it "transliterates fractions" do
    input = "\u{00BD} cup".to_slice # ½ cup
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("1/2 cup")
  end

  it "transliterates superscripts" do
    input = "x\u{00B2}".to_slice # x²
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("x2")
  end

  it "transliterates currency symbols" do
    input = "\u{20AC}100".to_slice # €100
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("EUR100")
  end

  it "transliterates ß to ss" do
    input = "Straße".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("Strasse")
  end

  it "stops on untransliterable character without //IGNORE" do
    # Chinese character has no transliteration to ASCII
    input = "A\u{4E2D}B".to_slice # A中B
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    end
  end

  it "passes through ASCII unchanged" do
    input = "Hello World 123!".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
    String.new(result).should eq("Hello World 123!")
  end
end

describe "//TRANSLIT//IGNORE" do
  it "transliterates what it can, drops the rest" do
    # Mix: accented (transliterable), Chinese (not transliterable), ASCII
    input = "café\u{4E2D}test".to_slice
    result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT//IGNORE")
    String.new(result).should eq("cafetest")
  end

  it "handles invalid bytes + unencodable chars" do
    # Invalid UTF-8 byte + accented char + Chinese
    input = Bytes.new(0)
    io = IO::Memory.new
    io.write(Bytes[0xFF])        # invalid
    io.write("é".to_slice)       # transliterable
    io.write("中".to_slice)       # untransliterable → skip
    io.write("ok".to_slice)      # ASCII
    combined = io.to_slice

    result = CharConv.convert(combined, "UTF-8", "ASCII//TRANSLIT//IGNORE")
    String.new(result).should eq("eok")
  end

  it "handles decode errors + encode errors together" do
    # Invalid EUC-JP bytes mixed with valid data
    input = Bytes[0x41, 0x80, 0x42] # A, invalid, B
    result = CharConv.convert(input, "EUC-JP", "ASCII//TRANSLIT//IGNORE")
    String.new(result).should eq("AB")
  end
end

describe "ConversionFlags" do
  it "parses //IGNORE flag" do
    flags = CharConv::Registry.parse_flags("ASCII//IGNORE")
    flags.ignore?.should be_true
    flags.translit?.should be_false
  end

  it "parses //TRANSLIT flag" do
    flags = CharConv::Registry.parse_flags("ASCII//TRANSLIT")
    flags.translit?.should be_true
    flags.ignore?.should be_false
  end

  it "parses combined flags" do
    flags = CharConv::Registry.parse_flags("ASCII//TRANSLIT//IGNORE")
    flags.translit?.should be_true
    flags.ignore?.should be_true
  end

  it "parses case-insensitively" do
    flags = CharConv::Registry.parse_flags("ASCII//translit//ignore")
    flags.translit?.should be_true
    flags.ignore?.should be_true
  end

  it "returns None for no suffix" do
    flags = CharConv::Registry.parse_flags("ASCII")
    flags.none?.should be_true
  end

  it "converter exposes flags" do
    conv = CharConv::Converter.new("UTF-8", "ASCII//IGNORE")
    conv.flags.ignore?.should be_true
  end
end

describe "Transliteration" do
  it "looks up known codepoints" do
    # é (U+00E9) → e
    result = CharConv::Transliteration.lookup(0x00E9_u32)
    result.should_not be_nil
    result.not_nil![0].should eq(0x0065_u32) # 'e'
  end

  it "returns nil for unknown codepoints" do
    # Chinese character — no transliteration
    result = CharConv::Transliteration.lookup(0x4E2D_u32)
    result.should be_nil
  end

  it "returns multi-char replacements" do
    # Æ (U+00C6) → AE
    result = CharConv::Transliteration.lookup(0x00C6_u32)
    result.should_not be_nil
    r = result.not_nil!
    r[0].should eq(0x0041_u32) # A
    r[1].should eq(0x0045_u32) # E
    r[2].should eq(0x0000_u32) # sentinel
  end
end
