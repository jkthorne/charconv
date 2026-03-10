require "./spec_helper"

describe "IO streaming conversion" do
  describe "Converter#convert(IO, IO)" do
    it "converts ASCII through IO" do
      input = IO::Memory.new("Hello, World!")
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
      conv.convert(input, output)
      output.rewind
      output.gets_to_end.should eq("Hello, World!")
    end

    it "converts non-ASCII Latin through IO" do
      input = IO::Memory.new("café résumé")
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
      conv.convert(input, output)
      output.rewind
      result = output.to_slice
      # Verify round-trip
      roundtrip = Iconvcr.convert(result, "ISO-8859-1", "UTF-8")
      String.new(roundtrip).should eq("café résumé")
    end

    it "handles empty input" do
      input = IO::Memory.new("")
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
      conv.convert(input, output)
      output.rewind
      output.to_slice.size.should eq(0)
    end

    it "handles multi-chunk input larger than buffer" do
      # Create input larger than the buffer size
      text = "ABCDéfgh" * 2000 # ~16KB of mixed ASCII/Latin
      input = IO::Memory.new(text)
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
      conv.convert(input, output, buffer_size: 256)
      output.rewind
      result = output.to_slice
      roundtrip = Iconvcr.convert(result, "ISO-8859-1", "UTF-8")
      String.new(roundtrip).should eq(text)
    end

    it "matches one-shot conversion result" do
      text = "Hello 世界! café"
      input_bytes = text.to_slice

      # One-shot
      one_shot = Iconvcr.convert(input_bytes, "UTF-8", "UTF-16BE")

      # IO streaming
      input = IO::Memory.new(text)
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "UTF-16BE")
      conv.convert(input, output)
      output.rewind

      output.to_slice.should eq(one_shot)
    end

    it "converts between single-byte encodings" do
      # Convert CP1252 → ISO-8859-1 via IO
      cp1252_bytes = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE9] # "Helloé"
      input = IO::Memory.new
      input.write(cp1252_bytes)
      input.rewind
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("CP1252", "ISO-8859-1")
      conv.convert(input, output)
      output.rewind
      output.to_slice.should eq(cp1252_bytes) # Same bytes for these characters
    end

    it "converts UTF-8 to UTF-16LE through IO" do
      text = "Hello!"
      input = IO::Memory.new(text)
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "UTF-16LE")
      conv.convert(input, output)
      output.rewind
      expected = Iconvcr.convert(text.to_slice, "UTF-8", "UTF-16LE")
      output.to_slice.should eq(expected)
    end

    it "handles small buffer with multibyte sequences at boundaries" do
      # Use a very small buffer to force splits in the middle of multibyte sequences
      text = "ééééé" # Each é is 2 bytes in UTF-8
      input = IO::Memory.new(text)
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
      conv.convert(input, output, buffer_size: 3) # Force mid-sequence splits
      output.rewind
      result = output.to_slice
      expected = Iconvcr.convert(text.to_slice, "UTF-8", "ISO-8859-1")
      result.should eq(expected)
    end

    it "works with //IGNORE flag" do
      # Input has chars not representable in ASCII
      text = "Hello café World"
      input = IO::Memory.new(text)
      output = IO::Memory.new
      conv = Iconvcr::Converter.new("UTF-8", "ASCII//IGNORE")
      conv.convert(input, output)
      output.rewind
      output.gets_to_end.should eq("Hello caf World")
    end
  end

  describe "Iconvcr.convert(IO, IO)" do
    it "provides module-level IO conversion" do
      input = IO::Memory.new("Hello!")
      output = IO::Memory.new
      Iconvcr.convert(input, output, "UTF-8", "ISO-8859-1")
      output.rewind
      output.gets_to_end.should eq("Hello!")
    end
  end
end
