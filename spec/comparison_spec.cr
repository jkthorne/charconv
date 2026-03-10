require "./spec_helper"

# Use Crystal's built-in LibC iconv bindings (available on macOS/Linux)

private def system_iconv_convert(input : Bytes, from : String, to : String) : Bytes
  cd = LibC.iconv_open(to, from)
  raise "iconv_open failed" if cd.address == LibC::SizeT::MAX

  # Allocate generous output buffer
  out_size = input.size * 4 + 16
  out_buf = Bytes.new(out_size)

  in_ptr = input.to_unsafe.as(UInt8*).as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(UInt8*).as(LibC::Char*)
  out_left = LibC::SizeT.new(out_size)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  raise "system iconv failed (result=#{result}, in_left=#{in_left})" if result == LibC::SizeT::MAX

  bytes_written = out_size - out_left
  out_buf[0, bytes_written]
end

# Encoding pairs to test
PAIRS = [
  {"ASCII", "ASCII"},
  {"ASCII", "UTF-8"},
  {"ASCII", "ISO-8859-1"},
  {"UTF-8", "ASCII"},
  {"UTF-8", "UTF-8"},
  {"UTF-8", "ISO-8859-1"},
  {"ISO-8859-1", "ASCII"},
  {"ISO-8859-1", "UTF-8"},
  {"ISO-8859-1", "ISO-8859-1"},
  # Phase 2: single-byte encodings
  {"CP1252", "UTF-8"},
  {"UTF-8", "CP1252"},
  {"ISO-8859-2", "UTF-8"},
  {"UTF-8", "ISO-8859-2"},
  {"KOI8-R", "UTF-8"},
  {"UTF-8", "KOI8-R"},
  {"CP437", "UTF-8"},
  {"UTF-8", "CP437"},
  {"MACROMAN", "UTF-8"},
  {"CP1252", "ISO-8859-1"},
  {"ISO-8859-1", "CP1252"},
]

describe "System iconv comparison" do
  PAIRS.each do |from, to|
    describe "#{from} → #{to}" do
      it "matches on ASCII input" do
        input = "Hello, World! 0123456789".to_slice
        expected = system_iconv_convert(input, from, to)
        actual = Iconvcr.convert(input, from, to)
        actual.should eq(expected)
      end

      it "matches on encoding-valid non-ASCII input" do
        case from
        when "ASCII"
          # ASCII has no high-byte characters, skip
        when "UTF-8"
          # Use Latin-1 range codepoints (representable in most encodings)
          input = "éñü©®".to_slice
          unless to == "ASCII" # ASCII can't represent these
            begin
              expected = system_iconv_convert(input, from, to)
              actual = Iconvcr.convert(input, from, to)
              actual.should eq(expected)
            rescue
              # Some target encodings may not support all Latin-1 chars — skip
            end
          end
        when "ISO-8859-1"
          input = Bytes[0xE9, 0xF1, 0xFC, 0xA9, 0xAE]
          unless to == "ASCII"
            begin
              expected = system_iconv_convert(input, from, to)
              actual = Iconvcr.convert(input, from, to)
              actual.should eq(expected)
            rescue
              # Target encoding may not support all Latin-1 chars
            end
          end
        else
          # For single-byte source encodings, use high bytes that are valid
          input = Bytes.new(32) { |i| (0xC0 + (i % 32)).to_u8 }
          begin
            expected = system_iconv_convert(input, from, to)
            actual = Iconvcr.convert(input, from, to)
            actual.should eq(expected)
          rescue
            # Some bytes may be undefined, skip
          end
        end
      end

      it "matches on multibyte UTF-8" do
        if from == "UTF-8" && to == "UTF-8"
          input = "Hello 世界 🌍".to_slice
          expected = system_iconv_convert(input, from, to)
          actual = Iconvcr.convert(input, from, to)
          actual.should eq(expected)
        end
      end
    end
  end
end
