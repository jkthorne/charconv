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

  # Reset
  LibC.iconv(cd, Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null,
             Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null)

  out_buf = Bytes.new(input.size * 8 + 64)
  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(out_buf.size)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  if result == ~LibC::SizeT.new(0) || in_left != 0
    nil
  else
    written = out_buf.size - out_left
    out_buf[0, written]
  end
end

describe "CJK Encodings" do
  # ===== Stateless CJK =====

  describe "EUC-JP" do
    it "converts Japanese text to UTF-8" do
      # "日本語" in EUC-JP: 0xC6FC 0xCBDC 0xB8EC
      input = Bytes[0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC]
      result = CharConv.convert(input, "EUC-JP", "UTF-8")
      expected = system_iconv(input, "EUC-JP", "UTF-8")
      result.should eq(expected) if expected
    end

    it "handles ASCII passthrough" do
      input = "Hello".to_slice
      result = CharConv.convert(input, "EUC-JP", "UTF-8")
      String.new(result).should eq("Hello")
    end

    it "round-trips through UTF-8" do
      # Encode a Japanese string to EUC-JP, then decode back
      utf8 = "日本語テスト".to_slice
      euc_jp = CharConv.convert(utf8, "UTF-8", "EUC-JP")
      back = CharConv.convert(euc_jp, "EUC-JP", "UTF-8")
      String.new(back).should eq("日本語テスト")
    end
  end

  describe "Shift_JIS" do
    it "converts Japanese text to UTF-8" do
      # "日本" in Shift_JIS: 0x93FA 0x967B
      input = Bytes[0x93, 0xFA, 0x96, 0x7B]
      result = CharConv.convert(input, "SHIFT_JIS", "UTF-8")
      expected = system_iconv(input, "SHIFT_JIS", "UTF-8")
      result.should eq(expected) if expected
    end

    it "handles half-width katakana" do
      # Half-width katakana ア (0xB1) in Shift_JIS
      input = Bytes[0xB1]
      result = CharConv.convert(input, "SHIFT_JIS", "UTF-8")
      expected = system_iconv(input, "SHIFT_JIS", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  describe "CP932" do
    it "converts Japanese text to UTF-8" do
      input = Bytes[0x93, 0xFA, 0x96, 0x7B]
      result = CharConv.convert(input, "CP932", "UTF-8")
      expected = system_iconv(input, "CP932", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  describe "GBK" do
    it "converts Chinese text to UTF-8" do
      # "中文" in GBK: 0xD6D0 0xCEC4
      input = Bytes[0xD6, 0xD0, 0xCE, 0xC4]
      result = CharConv.convert(input, "GBK", "UTF-8")
      expected = system_iconv(input, "GBK", "UTF-8")
      result.should eq(expected) if expected
    end

    it "round-trips through UTF-8" do
      utf8 = "中文测试".to_slice
      gbk = CharConv.convert(utf8, "UTF-8", "GBK")
      back = CharConv.convert(gbk, "GBK", "UTF-8")
      String.new(back).should eq("中文测试")
    end
  end

  describe "EUC-CN (GB2312)" do
    it "converts Chinese text to UTF-8" do
      input = Bytes[0xD6, 0xD0, 0xCE, 0xC4]
      result = CharConv.convert(input, "EUC-CN", "UTF-8")
      expected = system_iconv(input, "EUC-CN", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  describe "GB18030" do
    it "converts 2-byte GBK-compatible text" do
      input = Bytes[0xD6, 0xD0, 0xCE, 0xC4]
      result = CharConv.convert(input, "GB18030", "UTF-8")
      expected = system_iconv(input, "GB18030", "UTF-8")
      result.should eq(expected) if expected
    end

    it "handles 4-byte sequences" do
      # U+00E0 (à) in GB18030 is 4-byte: 81 30 89 30
      input = Bytes[0x81, 0x30, 0x89, 0x30]
      result = CharConv.convert(input, "GB18030", "UTF-8")
      expected = system_iconv(input, "GB18030", "UTF-8")
      result.should eq(expected) if expected
    end

    it "round-trips supplementary plane characters" do
      # U+20000 (CJK Unified Ideographs Extension B)
      utf8 = "\u{20000}".to_slice
      gb = CharConv.convert(utf8, "UTF-8", "GB18030")
      back = CharConv.convert(gb, "GB18030", "UTF-8")
      String.new(back).should eq("\u{20000}")
    end

    it "encodes BMP characters not in GBK as 4-byte" do
      # U+00E0 (à) is not in GBK, should get 4-byte GB18030
      utf8 = "à".to_slice
      gb = CharConv.convert(utf8, "UTF-8", "GB18030")
      expected = system_iconv(utf8, "UTF-8", "GB18030")
      gb.should eq(expected) if expected
    end
  end

  describe "Big5" do
    it "converts Traditional Chinese to UTF-8" do
      # "中文" in Big5: 0xA4A4 0xA4E5
      input = Bytes[0xA4, 0xA4, 0xA4, 0xE5]
      result = CharConv.convert(input, "BIG5", "UTF-8")
      expected = system_iconv(input, "BIG5", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  describe "CP950" do
    it "converts Traditional Chinese to UTF-8" do
      input = Bytes[0xA4, 0xA4, 0xA4, 0xE5]
      result = CharConv.convert(input, "CP950", "UTF-8")
      expected = system_iconv(input, "CP950", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  describe "EUC-KR" do
    it "converts Korean text to UTF-8" do
      # "한글" in EUC-KR: 0xC7D1 0xB1DB
      input = Bytes[0xC7, 0xD1, 0xB1, 0xDB]
      result = CharConv.convert(input, "EUC-KR", "UTF-8")
      expected = system_iconv(input, "EUC-KR", "UTF-8")
      result.should eq(expected) if expected
    end

    it "round-trips through UTF-8" do
      utf8 = "한글테스트".to_slice
      euckr = CharConv.convert(utf8, "UTF-8", "EUC-KR")
      back = CharConv.convert(euckr, "EUC-KR", "UTF-8")
      String.new(back).should eq("한글테스트")
    end
  end

  describe "CP949" do
    it "converts Korean text to UTF-8" do
      input = Bytes[0xC7, 0xD1, 0xB1, 0xDB]
      result = CharConv.convert(input, "CP949", "UTF-8")
      expected = system_iconv(input, "CP949", "UTF-8")
      result.should eq(expected) if expected
    end
  end

  # ===== Stateful CJK =====

  describe "ISO-2022-JP" do
    it "decodes ASCII mode" do
      input = "Hello".to_slice
      result = CharConv.convert(input, "ISO-2022-JP", "UTF-8")
      String.new(result).should eq("Hello")
    end

    it "decodes JIS X 0208 mode" do
      # ESC $ B (enter JIS X 0208) + 2 bytes + ESC ( B (return to ASCII)
      # "日" in JIS X 0208: row 0x46 col 0x7C → bytes 0x46 0x7C (shifted from EUC)
      input = Bytes[0x1B, 0x24, 0x42, 0x46, 0x7C, 0x1B, 0x28, 0x42]
      result = CharConv.convert(input, "ISO-2022-JP", "UTF-8")
      expected = system_iconv(input, "ISO-2022-JP", "UTF-8")
      result.should eq(expected) if expected
    end

    it "round-trips Japanese text" do
      # Get a known ISO-2022-JP sequence from system iconv
      utf8 = "日本".to_slice
      iso = system_iconv(utf8, "UTF-8", "ISO-2022-JP")
      if iso
        back = CharConv.convert(iso, "ISO-2022-JP", "UTF-8")
        String.new(back).should eq("日本")
      end
    end
  end

  describe "HZ" do
    it "decodes ASCII text" do
      input = "Hello".to_slice
      result = CharConv.convert(input, "HZ", "UTF-8")
      String.new(result).should eq("Hello")
    end

    it "decodes tilde escape" do
      # ~~ is a literal tilde
      input = Bytes[0x7E, 0x7E]
      result = CharConv.convert(input, "HZ", "UTF-8")
      String.new(result).should eq("~")
    end

    it "round-trips Chinese text" do
      utf8 = "中文".to_slice
      hz = system_iconv(utf8, "UTF-8", "HZ")
      if hz
        back = CharConv.convert(hz, "HZ", "UTF-8")
        String.new(back).should eq("中文")
      end
    end
  end

  describe "ISO-2022-KR" do
    it "round-trips Korean text via CharConv" do
      utf8 = "한글".to_slice
      iso = CharConv.convert(utf8, "UTF-8", "ISO-2022-KR")
      back = CharConv.convert(iso, "ISO-2022-KR", "UTF-8")
      String.new(back).should eq("한글")
    end

    it "decodes known ISO-2022-KR sequence" do
      # ESC $ ) C (designate) + SO + 47 51 (한) + 31 5B (글) + SI
      input = Bytes[0x1B, 0x24, 0x29, 0x43, 0x0E, 0x47, 0x51, 0x31, 0x5B, 0x0F]
      result = CharConv.convert(input, "ISO-2022-KR", "UTF-8")
      String.new(result).should eq("한글")
    end
  end

end

# ===== Comparison tests: verify against system iconv =====

CJK_TEST_ENCODINGS = [
      {"EUC-JP", [
        Bytes[0x41],                          # ASCII
        Bytes[0xC6, 0xFC],                    # JIS X 0208
        Bytes[0x8E, 0xB1],                    # Half-width katakana
        Bytes[0x41, 0xC6, 0xFC, 0x42],        # Mixed
      ]},
      {"SHIFT_JIS", [
        Bytes[0x41],
        Bytes[0x93, 0xFA],
        Bytes[0xB1],                          # Half-width katakana
      ]},
      {"GBK", [
        Bytes[0x41],
        Bytes[0xD6, 0xD0],
        Bytes[0xCE, 0xC4],
      ]},
      {"EUC-CN", [
        Bytes[0x41],
        Bytes[0xD6, 0xD0],
      ]},
      {"BIG5", [
        Bytes[0x41],
        Bytes[0xA4, 0xA4],
      ]},
      {"EUC-KR", [
        Bytes[0x41],
        Bytes[0xC7, 0xD1],
      ]},
      {"CP949", [
        Bytes[0x41],
        Bytes[0xC7, 0xD1],
      ]},
    ]

describe "CJK comparison with system iconv" do
  CJK_TEST_ENCODINGS.each do |encoding, test_inputs|
    test_inputs.each_with_index do |input, idx|
      it "#{encoding} sample #{idx} matches system iconv" do
        expected = system_iconv(input, encoding, "UTF-8")
        next unless expected
        result = CharConv.convert(input, encoding, "UTF-8")
        result.should eq(expected)
      end
    end
  end
end
