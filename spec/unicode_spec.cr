require "./spec_helper"

describe "UTF-16BE" do
  it "encodes and decodes ASCII" do
    input = "Hello".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-16BE")
    encoded.should eq(Bytes[0x00, 0x48, 0x00, 0x65, 0x00, 0x6C, 0x00, 0x6C, 0x00, 0x6F])
    decoded = CharConv.convert(encoded, "UTF-16BE", "UTF-8")
    decoded.should eq(input)
  end

  it "handles BMP characters" do
    # U+00E9 (é) in UTF-16BE: 00 E9
    input = Bytes[0x00, 0xE9]
    result = CharConv.convert(input, "UTF-16BE", "UTF-8")
    result.should eq("é".to_slice)
  end

  it "handles supplementary characters via surrogate pairs" do
    # U+1F600 (😀) in UTF-16BE: D8 3D DE 00
    input = Bytes[0xD8, 0x3D, 0xDE, 0x00]
    result = CharConv.convert(input, "UTF-16BE", "UTF-8")
    result.should eq("😀".to_slice)
  end

  it "round-trips supplementary characters" do
    utf8 = "😀🌍".to_slice
    encoded = CharConv.convert(utf8, "UTF-8", "UTF-16BE")
    decoded = CharConv.convert(encoded, "UTF-16BE", "UTF-8")
    decoded.should eq(utf8)
  end

  it "rejects lone low surrogate" do
    input = Bytes[0xDC, 0x00]
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-16BE", "UTF-8")
    end
  end
end

describe "UTF-16LE" do
  it "encodes and decodes ASCII" do
    input = "Hi".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-16LE")
    encoded.should eq(Bytes[0x48, 0x00, 0x69, 0x00])
    decoded = CharConv.convert(encoded, "UTF-16LE", "UTF-8")
    decoded.should eq(input)
  end

  it "handles supplementary characters" do
    # U+1F600 in UTF-16LE: 3D D8 00 DE
    input = Bytes[0x3D, 0xD8, 0x00, 0xDE]
    result = CharConv.convert(input, "UTF-16LE", "UTF-8")
    result.should eq("😀".to_slice)
  end
end

describe "UTF-16 (BOM)" do
  it "decodes with BE BOM" do
    # FE FF BOM + U+0041
    input = Bytes[0xFE, 0xFF, 0x00, 0x41]
    result = CharConv.convert(input, "UTF-16", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "decodes with LE BOM" do
    # FF FE BOM + U+0041 in LE
    input = Bytes[0xFF, 0xFE, 0x41, 0x00]
    result = CharConv.convert(input, "UTF-16", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "defaults to BE when no BOM" do
    input = Bytes[0x00, 0x41]
    result = CharConv.convert(input, "UTF-16", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "encode prepends BOM" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-16")
    # Should start with FE FF (BE BOM)
    encoded[0].should eq(0xFE_u8)
    encoded[1].should eq(0xFF_u8)
    encoded[2].should eq(0x00_u8)
    encoded[3].should eq(0x41_u8)
  end
end

describe "UTF-32BE" do
  it "encodes and decodes ASCII" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-32BE")
    encoded.should eq(Bytes[0x00, 0x00, 0x00, 0x41])
    decoded = CharConv.convert(encoded, "UTF-32BE", "UTF-8")
    decoded.should eq(input)
  end

  it "handles supplementary characters" do
    # U+1F600 in UTF-32BE: 00 01 F6 00
    input = Bytes[0x00, 0x01, 0xF6, 0x00]
    result = CharConv.convert(input, "UTF-32BE", "UTF-8")
    result.should eq("😀".to_slice)
  end

  it "rejects surrogates" do
    input = Bytes[0x00, 0x00, 0xD8, 0x00]
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-32BE", "UTF-8")
    end
  end

  it "rejects values > U+10FFFF" do
    input = Bytes[0x00, 0x11, 0x00, 0x00]
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-32BE", "UTF-8")
    end
  end
end

describe "UTF-32LE" do
  it "encodes and decodes" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-32LE")
    encoded.should eq(Bytes[0x41, 0x00, 0x00, 0x00])
    decoded = CharConv.convert(encoded, "UTF-32LE", "UTF-8")
    decoded.should eq(input)
  end
end

describe "UTF-32 (BOM)" do
  it "decodes with BE BOM" do
    input = Bytes[0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41]
    result = CharConv.convert(input, "UTF-32", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "decodes with LE BOM" do
    input = Bytes[0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]
    result = CharConv.convert(input, "UTF-32", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "encode prepends BOM" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UTF-32")
    encoded[0..3].should eq(Bytes[0x00, 0x00, 0xFE, 0xFF])
    encoded[4..7].should eq(Bytes[0x00, 0x00, 0x00, 0x41])
  end
end

describe "UCS-2 vs UTF-16" do
  it "UCS-2BE rejects surrogates" do
    # Surrogate 0xD800 should be rejected by UCS-2
    input = Bytes[0xD8, 0x00]
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UCS-2BE", "UTF-8")
    end
  end

  it "UCS-2BE handles BMP" do
    input = Bytes[0x00, 0xE9]
    result = CharConv.convert(input, "UCS-2BE", "UTF-8")
    result.should eq("é".to_slice)
  end

  it "UCS-2 encode rejects cp > 0xFFFF" do
    # U+1F600 can't be represented in UCS-2
    utf8 = "😀".to_slice
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(utf8, "UTF-8", "UCS-2BE")
    end
  end

  it "UTF-16BE handles surrogates (supplementary)" do
    # U+1F600 via surrogate pair
    input = Bytes[0xD8, 0x3D, 0xDE, 0x00]
    result = CharConv.convert(input, "UTF-16BE", "UTF-8")
    result.should eq("😀".to_slice)
  end
end

describe "UCS-2 (BOM)" do
  it "decodes with BE BOM" do
    input = Bytes[0xFE, 0xFF, 0x00, 0x41]
    result = CharConv.convert(input, "UCS-2", "UTF-8")
    result.should eq("A".to_slice)
  end

  it "decodes with LE BOM" do
    input = Bytes[0xFF, 0xFE, 0x41, 0x00]
    result = CharConv.convert(input, "UCS-2", "UTF-8")
    result.should eq("A".to_slice)
  end
end

describe "UCS-2-INTERNAL / UCS-2-SWAPPED" do
  it "UCS-2-INTERNAL uses native endianness" do
    input = "é".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UCS-2-INTERNAL")
    # On little-endian: 0xE9 0x00
    {% if flag?(:little_endian) %}
      encoded.should eq(Bytes[0xE9, 0x00])
    {% else %}
      encoded.should eq(Bytes[0x00, 0xE9])
    {% end %}
  end

  it "UCS-2-SWAPPED uses opposite endianness" do
    input = "é".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UCS-2-SWAPPED")
    {% if flag?(:little_endian) %}
      encoded.should eq(Bytes[0x00, 0xE9])
    {% else %}
      encoded.should eq(Bytes[0xE9, 0x00])
    {% end %}
  end
end

describe "UCS-4 (aliases for UTF-32)" do
  it "UCS-4BE encodes like UTF-32BE" do
    input = "A".to_slice
    result = CharConv.convert(input, "UTF-8", "UCS-4BE")
    result.should eq(Bytes[0x00, 0x00, 0x00, 0x41])
  end

  it "UCS-4LE encodes like UTF-32LE" do
    input = "A".to_slice
    result = CharConv.convert(input, "UTF-8", "UCS-4LE")
    result.should eq(Bytes[0x41, 0x00, 0x00, 0x00])
  end

  it "UCS-4 (BOM) encode prepends BOM" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UCS-4")
    encoded[0..3].should eq(Bytes[0x00, 0x00, 0xFE, 0xFF])
  end

  it "UCS-4-INTERNAL uses native endianness" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UCS-4-INTERNAL")
    {% if flag?(:little_endian) %}
      encoded.should eq(Bytes[0x41, 0x00, 0x00, 0x00])
    {% else %}
      encoded.should eq(Bytes[0x00, 0x00, 0x00, 0x41])
    {% end %}
  end

  it "UCS-4-SWAPPED uses opposite endianness" do
    input = "A".to_slice
    encoded = CharConv.convert(input, "UTF-8", "UCS-4-SWAPPED")
    {% if flag?(:little_endian) %}
      encoded.should eq(Bytes[0x00, 0x00, 0x00, 0x41])
    {% else %}
      encoded.should eq(Bytes[0x41, 0x00, 0x00, 0x00])
    {% end %}
  end
end

describe "C99" do
  it "decodes \\u escape" do
    input = "\\u00e9".to_slice
    result = CharConv.convert(input, "C99", "UTF-8")
    result.should eq("é".to_slice)
  end

  it "decodes \\U escape" do
    input = "\\U0001f600".to_slice
    result = CharConv.convert(input, "C99", "UTF-8")
    result.should eq("😀".to_slice)
  end

  it "passes ASCII through" do
    input = "Hello".to_slice
    result = CharConv.convert(input, "C99", "UTF-8")
    result.should eq("Hello".to_slice)
  end

  it "encodes non-ASCII to \\u" do
    input = "é".to_slice
    result = CharConv.convert(input, "UTF-8", "C99")
    result.should eq("\\u00e9".to_slice)
  end

  it "encodes supplementary to \\U" do
    input = "😀".to_slice
    result = CharConv.convert(input, "UTF-8", "C99")
    result.should eq("\\U0001f600".to_slice)
  end

  it "encodes ASCII directly" do
    input = "Hello".to_slice
    result = CharConv.convert(input, "UTF-8", "C99")
    result.should eq("Hello".to_slice)
  end
end

describe "JAVA" do
  it "decodes \\u escape" do
    input = "\\u00e9".to_slice
    result = CharConv.convert(input, "JAVA", "UTF-8")
    result.should eq("é".to_slice)
  end

  it "decodes surrogate pair" do
    input = "\\ud83d\\ude00".to_slice
    result = CharConv.convert(input, "JAVA", "UTF-8")
    result.should eq("😀".to_slice)
  end

  it "passes ASCII through" do
    input = "Hello".to_slice
    result = CharConv.convert(input, "JAVA", "UTF-8")
    result.should eq("Hello".to_slice)
  end

  it "encodes BMP to \\u" do
    input = "é".to_slice
    result = CharConv.convert(input, "UTF-8", "JAVA")
    result.should eq("\\u00e9".to_slice)
  end

  it "encodes supplementary as surrogate pair" do
    input = "😀".to_slice
    result = CharConv.convert(input, "UTF-8", "JAVA")
    result.should eq("\\ud83d\\ude00".to_slice)
  end
end

describe "UTF-7" do
  it "passes ASCII through" do
    input = "Hello".to_slice
    result = CharConv.convert(input, "UTF-7", "UTF-8")
    result.should eq("Hello".to_slice)
  end

  it "decodes +- as literal +" do
    input = "+-".to_slice
    result = CharConv.convert(input, "UTF-7", "UTF-8")
    result.should eq("+".to_slice)
  end

  it "encodes ASCII directly" do
    input = "Hello".to_slice
    result = CharConv.convert(input, "UTF-8", "UTF-7")
    result.should eq("Hello".to_slice)
  end

  it "round-trips BMP characters" do
    utf8 = "é".to_slice
    encoded = CharConv.convert(utf8, "UTF-8", "UTF-7")
    decoded = CharConv.convert(encoded, "UTF-7", "UTF-8")
    decoded.should eq(utf8)
  end

  it "round-trips mixed ASCII and non-ASCII" do
    utf8 = "Hello, 世界!".to_slice
    encoded = CharConv.convert(utf8, "UTF-8", "UTF-7")
    decoded = CharConv.convert(encoded, "UTF-7", "UTF-8")
    decoded.should eq(utf8)
  end
end

describe "Empty input" do
  it "handles empty UTF-16BE" do
    result = CharConv.convert(Bytes.empty, "UTF-16BE", "UTF-8")
    result.size.should eq(0)
  end

  it "handles empty UTF-32LE" do
    result = CharConv.convert(Bytes.empty, "UTF-32LE", "UTF-8")
    result.size.should eq(0)
  end

  it "handles empty C99" do
    result = CharConv.convert(Bytes.empty, "C99", "UTF-8")
    result.size.should eq(0)
  end
end

describe "Truncated input" do
  it "rejects truncated UTF-16BE" do
    input = Bytes[0x00] # only 1 byte
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-16BE", "UTF-8")
    end
  end

  it "rejects truncated UTF-32BE" do
    input = Bytes[0x00, 0x00, 0x00] # only 3 bytes
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-32BE", "UTF-8")
    end
  end

  it "rejects truncated surrogate pair in UTF-16BE" do
    # High surrogate without low surrogate
    input = Bytes[0xD8, 0x3D]
    expect_raises(CharConv::ConversionError) do
      CharConv.convert(input, "UTF-16BE", "UTF-8")
    end
  end
end

describe "Encoding support" do
  it "recognizes all new encodings" do
    %w[UTF-16BE UTF-16LE UTF-16 UTF-32BE UTF-32LE UTF-32
       UCS-2 UCS-2BE UCS-2LE UCS-2-INTERNAL UCS-2-SWAPPED
       UCS-4 UCS-4BE UCS-4LE UCS-4-INTERNAL UCS-4-SWAPPED
       UTF-7 C99 JAVA].each do |name|
      CharConv.encoding_supported?(name).should be_true, "#{name} should be supported"
    end
  end

  it "recognizes aliases" do
    CharConv.encoding_supported?("UNICODE-1-1").should be_true
    CharConv.encoding_supported?("UNICODE-1-1-UTF-7").should be_true
    CharConv.encoding_supported?("CSUNICODE").should be_true
    CharConv.encoding_supported?("CSUCS4").should be_true
  end
end
