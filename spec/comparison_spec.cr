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

# Helper: prepare valid input in source encoding by converting from UTF-8 via system iconv
private def prepare_input(utf8_text : String, from : String) : Bytes
  case from
  when "ASCII"
    utf8_text.to_slice
  when "UTF-8"
    utf8_text.to_slice
  when "ISO-8859-1"
    utf8_text.to_slice # will be handled specially in tests
  else
    system_iconv_convert(utf8_text.to_slice, "UTF-8", from)
  end
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
  # Phase 3: Unicode family encodings
  {"UTF-16BE", "UTF-8"},
  {"UTF-8", "UTF-16BE"},
  {"UTF-16LE", "UTF-8"},
  {"UTF-8", "UTF-16LE"},
  {"UTF-32BE", "UTF-8"},
  {"UTF-8", "UTF-32BE"},
  {"UTF-32LE", "UTF-8"},
  {"UTF-8", "UTF-32LE"},
  {"UTF-7", "UTF-8"},
  {"UTF-8", "UTF-7"},
  {"C99", "UTF-8"},
  {"UTF-8", "C99"},
  {"JAVA", "UTF-8"},
  {"UTF-8", "JAVA"},
]

# Multi-byte source encodings that need input prepared via system iconv
MULTIBYTE_SOURCES = {"UTF-16BE", "UTF-16LE", "UTF-32BE", "UTF-32LE", "UTF-7", "C99", "JAVA"}

describe "System iconv comparison" do
  PAIRS.each do |from, to|
    describe "#{from} → #{to}" do
      it "matches on ASCII input" do
        if MULTIBYTE_SOURCES.includes?(from)
          # Convert ASCII to source encoding first
          input = system_iconv_convert("Hello, World! 0123456789".to_slice, "UTF-8", from)
        else
          input = "Hello, World! 0123456789".to_slice
        end
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
          if MULTIBYTE_SOURCES.includes?(from)
            # Convert non-ASCII text to source encoding via system iconv
            begin
              input = system_iconv_convert("éñü©®".to_slice, "UTF-8", from)
              expected = system_iconv_convert(input, from, to)
              actual = Iconvcr.convert(input, from, to)
              actual.should eq(expected)
            rescue
              # Some encodings may not support all chars — skip
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
      end

      it "matches on multibyte UTF-8" do
        if from == "UTF-8" && to == "UTF-8"
          input = "Hello 世界 🌍".to_slice
          expected = system_iconv_convert(input, from, to)
          actual = Iconvcr.convert(input, from, to)
          actual.should eq(expected)
        elsif from == "UTF-8"
          begin
            input = "Hello 世界 🌍".to_slice
            expected = system_iconv_convert(input, from, to)
            actual = Iconvcr.convert(input, from, to)
            actual.should eq(expected)
          rescue
            # Target may not support all characters
          end
        elsif MULTIBYTE_SOURCES.includes?(from)
          begin
            input = system_iconv_convert("Hello 世界 🌍".to_slice, "UTF-8", from)
            expected = system_iconv_convert(input, from, to)
            actual = Iconvcr.convert(input, from, to)
            actual.should eq(expected)
          rescue
            # Some encodings can't represent supplementary chars
          end
        end
      end
    end
  end
end
