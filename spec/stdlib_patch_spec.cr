require "spec"
require "../src/charconv/stdlib"

describe "stdlib patch" do
  describe "String#encode" do
    it "encodes ASCII to ISO-8859-1" do
      "Hello".encode("ISO-8859-1").should eq "Hello".to_slice
    end

    it "encodes non-ASCII to ISO-8859-1" do
      result = "café".encode("ISO-8859-1")
      result.should eq Bytes[0x63, 0x61, 0x66, 0xE9]
    end

    it "encodes to Shift_JIS" do
      result = "日本語".encode("Shift_JIS")
      result.size.should be > 0
    end

    it "encodes to UTF-16BE" do
      result = "Hi".encode("UTF-16BE")
      result.should eq Bytes[0x00, 0x48, 0x00, 0x69]
    end
  end

  describe "String.new(bytes, encoding)" do
    it "decodes ISO-8859-1 to String" do
      bytes = Bytes[0x63, 0x61, 0x66, 0xE9]
      String.new(bytes, "ISO-8859-1").should eq "café"
    end

    it "decodes Shift_JIS to String" do
      # "日本語" in Shift_JIS
      encoded = "日本語".encode("Shift_JIS")
      String.new(encoded, "Shift_JIS").should eq "日本語"
    end

    it "decodes UTF-16BE to String" do
      bytes = Bytes[0x00, 0x48, 0x00, 0x69]
      String.new(bytes, "UTF-16BE").should eq "Hi"
    end

    it "decodes Windows-1252 to String" do
      # 0x93 = left double quotation mark in CP1252
      bytes = Bytes[0x93, 0x48, 0x69, 0x94]
      result = String.new(bytes, "WINDOWS-1252")
      result.should eq "\u201CHi\u201D"
    end
  end

  describe "roundtrip" do
    it "roundtrips through ISO-8859-1" do
      original = "café"
      encoded = original.encode("ISO-8859-1")
      decoded = String.new(encoded, "ISO-8859-1")
      decoded.should eq original
    end

    it "roundtrips through EUC-JP" do
      original = "日本語テスト"
      encoded = original.encode("EUC-JP")
      decoded = String.new(encoded, "EUC-JP")
      decoded.should eq original
    end

    it "roundtrips through GB18030" do
      original = "中文测试"
      encoded = original.encode("GB18030")
      decoded = String.new(encoded, "GB18030")
      decoded.should eq original
    end

    it "roundtrips through UTF-16LE" do
      original = "Hello, 世界!"
      encoded = original.encode("UTF-16LE")
      decoded = String.new(encoded, "UTF-16LE")
      decoded.should eq original
    end

    it "roundtrips through CP949 (Korean)" do
      original = "한국어"
      encoded = original.encode("CP949")
      decoded = String.new(encoded, "CP949")
      decoded.should eq original
    end
  end

  describe "invalid byte handling" do
    it "raises on invalid sequence by default" do
      # 0xFF is not valid UTF-8
      bytes = Bytes[0x48, 0xFF, 0x69]
      expect_raises(ArgumentError) do
        String.new(bytes, "UTF-8")
      end
    end

    it "skips invalid bytes with :skip" do
      bytes = Bytes[0x48, 0xFF, 0x69]
      result = String.new(bytes, "UTF-8", invalid: :skip)
      result.should eq "Hi"
    end

    it "raises on unencodable character by default" do
      # é (U+00E9) is not representable in ASCII
      expect_raises(ArgumentError) do
        "café".encode("ASCII")
      end
    end

    it "skips unencodable characters with :skip" do
      result = "café".encode("ASCII", invalid: :skip)
      result.should eq "caf".to_slice
    end
  end

  describe "IO encoding" do
    it "reads with encoding" do
      raw = "café".encode("ISO-8859-1")
      io = IO::Memory.new(raw)
      io.set_encoding("ISO-8859-1")
      io.gets_to_end.should eq "café"
    end

    it "reads Shift_JIS through IO" do
      raw = "日本語".encode("Shift_JIS")
      io = IO::Memory.new(raw)
      io.set_encoding("Shift_JIS")
      io.gets_to_end.should eq "日本語"
    end
  end

  describe "encoding validation" do
    it "raises on unknown encoding" do
      expect_raises(ArgumentError, "Invalid encoding") do
        "test".encode("FAKE-ENCODING-123")
      end
    end
  end
end
