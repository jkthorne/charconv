require "./spec_helper"

# Exhaustive byte-level correctness test for all single-byte encodings.
# Compares every byte 0x00-0xFF against system iconv for both directions.

private def system_iconv_byte(byte : UInt8, from : String, to : String) : Bytes?
  cd = LibC.iconv_open(to, from)
  return nil if cd.address == LibC::SizeT::MAX

  input = Bytes[byte]
  out_buf = Bytes.new(16)

  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(1)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(16)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  if result == LibC::SizeT::MAX
    nil
  else
    bytes_written = 16 - out_left
    out_buf[0, bytes_written]
  end
end

private def system_iconv_convert(input : Bytes, from : String, to : String) : Bytes?
  cd = LibC.iconv_open(to, from)
  return nil if cd.address == LibC::SizeT::MAX

  out_size = input.size * 4 + 16
  out_buf = Bytes.new(out_size)

  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(out_size)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)

  if result == LibC::SizeT::MAX
    nil
  else
    bytes_written = out_size - out_left
    out_buf[0, bytes_written]
  end
end

# All single-byte encodings with their iconv names
SINGLE_BYTE_ENCODINGS = [
  {"ISO-8859-2", true}, {"ISO-8859-3", true}, {"ISO-8859-4", true},
  {"ISO-8859-5", true}, {"ISO-8859-6", true}, {"ISO-8859-7", true},
  {"ISO-8859-8", true}, {"ISO-8859-9", true}, {"ISO-8859-10", true},
  {"ISO-8859-11", true}, {"ISO-8859-13", true}, {"ISO-8859-14", true},
  {"ISO-8859-15", true}, {"ISO-8859-16", true},
  {"CP1250", true}, {"CP1251", true}, {"CP1252", true}, {"CP1253", true},
  {"CP1254", true}, {"CP1255", true}, {"CP1256", true}, {"CP1257", true},
  {"CP1258", true},
  {"KOI8-R", true}, {"KOI8-U", true}, {"KOI8-RU", true},
  {"MACROMAN", false}, {"MACCENTRALEUROPE", false}, {"MACICELAND", false},
  {"MACCROATIAN", false}, {"MACROMANIA", false}, {"MACCYRILLIC", false},
  {"MACUKRAINE", false}, {"MACGREEK", false}, {"MACTURKISH", false},
  {"MACHEBREW", false}, {"MACARABIC", false}, {"MACTHAI", false},
  {"CP437", true}, {"CP737", true}, {"CP775", true}, {"CP850", true},
  {"CP852", true}, {"CP855", true}, {"CP857", true}, {"CP858", true},
  {"CP860", true}, {"CP861", true}, {"CP862", true}, {"CP863", true},
  {"CP864", false}, {"CP865", true}, {"CP866", true}, {"CP869", true},
  {"CP874", true}, {"TIS-620", true},
  {"VISCII", false},
  {"ARMSCII-8", true}, {"GEORGIAN-ACADEMY", true}, {"GEORGIAN-PS", true},
  {"HP-ROMAN8", true}, {"NEXTSTEP", true}, {"PT154", true}, {"KOI8-T", true},
  # Phase 5: EBCDIC (NOT ASCII supersets)
  {"CP037", false}, {"CP273", false}, {"CP277", false}, {"CP278", false},
  {"CP280", false}, {"CP284", false}, {"CP285", false}, {"CP297", false},
  {"CP423", false}, {"CP424", false}, {"CP500", false}, {"CP905", false},
  {"CP1026", false},
  # Phase 5: ASCII-superset single-byte
  {"CP856", true}, {"CP922", true}, {"CP853", true}, {"CP1046", true},
  {"CP1124", true}, {"CP1125", true}, {"CP1129", true}, {"CP1131", true},
  {"CP1133", true}, {"CP1161", true}, {"CP1162", true}, {"CP1163", true},
  {"ATARIST", true}, {"KZ-1048", true}, {"MULELAO-1", true}, {"RISCOS-LATIN1", true},
  # Phase 5: Non-ASCII non-EBCDIC
  {"TCVN", false},
]

describe "Exhaustive single-byte encoding correctness" do
  SINGLE_BYTE_ENCODINGS.each do |encoding, is_ascii_superset|
    describe encoding do
      it "decodes all 256 bytes to UTF-8 matching system iconv" do
        mismatches = 0
        (0x00..0xFF).each do |byte_val|
          b = byte_val.to_u8
          sys_result = system_iconv_byte(b, encoding, "UTF-8")

          begin
            our_result = CharConv.convert(Bytes[b], encoding, "UTF-8")
            if sys_result
              unless our_result == sys_result
                mismatches += 1
                STDERR.puts "  MISMATCH #{encoding} byte 0x#{byte_val.to_s(16).rjust(2, '0')}: " \
                            "ours=#{our_result.map(&.to_s(16)).join(" ")} " \
                            "sys=#{sys_result.map(&.to_s(16)).join(" ")}" if mismatches <= 5
              end
            else
              # System iconv failed but we succeeded — mismatch
              mismatches += 1
              STDERR.puts "  MISMATCH #{encoding} byte 0x#{byte_val.to_s(16).rjust(2, '0')}: " \
                          "ours succeeded, system failed" if mismatches <= 5
            end
          rescue CharConv::ConversionError
            unless sys_result.nil?
              mismatches += 1
              STDERR.puts "  MISMATCH #{encoding} byte 0x#{byte_val.to_s(16).rjust(2, '0')}: " \
                          "ours=ILSEQ sys=#{sys_result.map(&.to_s(16)).join(" ")}" if mismatches <= 5
            end
            # Both failed — OK
          end
        end
        mismatches.should eq(0), "#{mismatches} byte(s) differ from system iconv for #{encoding}"
      end

      it "encodes BMP codepoints to #{encoding} with correct round-trip" do
        # For each byte that decodes successfully, encode the codepoint back and verify
        # round-trip correctness: our encoded byte must decode to the same codepoint.
        # We also check against system iconv where possible, but accept differences when:
        # - System iconv does transliteration (multi-byte output for single-byte encoding)
        # - Multiple bytes decode to the same codepoint (both encodings are valid)
        mismatches = 0
        (0x00..0xFF).each do |byte_val|
          b = byte_val.to_u8
          # Get the UTF-8 representation from system iconv
          utf8_bytes = system_iconv_byte(b, encoding, "UTF-8")
          next unless utf8_bytes
          next if utf8_bytes.empty?

          # Now try encoding the UTF-8 back to the target encoding
          sys_encoded = system_iconv_convert(utf8_bytes, "UTF-8", encoding)
          next unless sys_encoded
          # Skip transliteration: system iconv produced multi-byte output for single-byte encoding
          next if sys_encoded.size != 1

          begin
            our_encoded = CharConv.convert(utf8_bytes, "UTF-8", encoding)
            if our_encoded != sys_encoded
              # Our byte differs — verify round-trip: decode our byte back and compare codepoints
              our_roundtrip = system_iconv_byte(our_encoded[0], encoding, "UTF-8")
              if our_roundtrip != utf8_bytes
                mismatches += 1
                STDERR.puts "  ENCODE MISMATCH #{encoding} byte 0x#{byte_val.to_s(16).rjust(2, '0')}: " \
                            "ours=#{our_encoded.map(&.to_s(16)).join(" ")} " \
                            "sys=#{sys_encoded.map(&.to_s(16)).join(" ")} " \
                            "(round-trip differs)" if mismatches <= 5
              end
            end
          rescue CharConv::ConversionError
            mismatches += 1
            STDERR.puts "  ENCODE MISMATCH #{encoding} byte 0x#{byte_val.to_s(16).rjust(2, '0')}: " \
                        "ours=ERROR sys=#{sys_encoded.map(&.to_s(16)).join(" ")}" if mismatches <= 5
          end
        end
        mismatches.should eq(0), "#{mismatches} encode mismatch(es) for #{encoding}"
      end
    end
  end
end
