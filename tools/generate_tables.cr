#!/usr/bin/env crystal

# Generates single-byte encoding tables by probing system iconv.
# Probes BOTH directions: decode (encoding→UTF-32LE) and encode (UTF-8→encoding).
# Output: src/iconvcr/tables/single_byte.cr

# LibC iconv bindings are already available in Crystal stdlib

ENCODINGS = {
  {"ISO_8859_2", "ISO-8859-2"},
  {"ISO_8859_3", "ISO-8859-3"},
  {"ISO_8859_4", "ISO-8859-4"},
  {"ISO_8859_5", "ISO-8859-5"},
  {"ISO_8859_6", "ISO-8859-6"},
  {"ISO_8859_7", "ISO-8859-7"},
  {"ISO_8859_8", "ISO-8859-8"},
  {"ISO_8859_9", "ISO-8859-9"},
  {"ISO_8859_10", "ISO-8859-10"},
  {"ISO_8859_11", "ISO-8859-11"},
  {"ISO_8859_13", "ISO-8859-13"},
  {"ISO_8859_14", "ISO-8859-14"},
  {"ISO_8859_15", "ISO-8859-15"},
  {"ISO_8859_16", "ISO-8859-16"},
  {"CP1250", "CP1250"},
  {"CP1251", "CP1251"},
  {"CP1252", "CP1252"},
  {"CP1253", "CP1253"},
  {"CP1254", "CP1254"},
  {"CP1255", "CP1255"},
  {"CP1256", "CP1256"},
  {"CP1257", "CP1257"},
  {"CP1258", "CP1258"},
  {"KOI8_R", "KOI8-R"},
  {"KOI8_U", "KOI8-U"},
  {"KOI8_RU", "KOI8-RU"},
  {"MAC_ROMAN", "MACROMAN"},
  {"MAC_CENTRAL_EUROPE", "MACCENTRALEUROPE"},
  {"MAC_ICELAND", "MACICELAND"},
  {"MAC_CROATIAN", "MACCROATIAN"},
  {"MAC_ROMANIA", "MACROMANIA"},
  {"MAC_CYRILLIC", "MACCYRILLIC"},
  {"MAC_UKRAINE", "MACUKRAINE"},
  {"MAC_GREEK", "MACGREEK"},
  {"MAC_TURKISH", "MACTURKISH"},
  {"MAC_HEBREW", "MACHEBREW"},
  {"MAC_ARABIC", "MACARABIC"},
  {"MAC_THAI", "MACTHAI"},
  {"CP437", "CP437"},
  {"CP737", "CP737"},
  {"CP775", "CP775"},
  {"CP850", "CP850"},
  {"CP852", "CP852"},
  {"CP855", "CP855"},
  {"CP857", "CP857"},
  {"CP858", "CP858"},
  {"CP860", "CP860"},
  {"CP861", "CP861"},
  {"CP862", "CP862"},
  {"CP863", "CP863"},
  {"CP864", "CP864"},
  {"CP865", "CP865"},
  {"CP866", "CP866"},
  {"CP869", "CP869"},
  {"CP874", "CP874"},
  {"TIS_620", "TIS-620"},
  {"VISCII", "VISCII"},
  {"ARMSCII_8", "ARMSCII-8"},
  {"GEORGIAN_ACADEMY", "GEORGIAN-ACADEMY"},
  {"GEORGIAN_PS", "GEORGIAN-PS"},
  {"HP_ROMAN8", "HP-ROMAN8"},
  {"NEXTSTEP", "NEXTSTEP"},
  {"PT154", "PT154"},
  {"KOI8_T", "KOI8-T"},
  # Phase 5: EBCDIC encodings
  {"CP037", "CP037"},
  {"CP273", "CP273"},
  {"CP277", "CP277"},
  {"CP278", "CP278"},
  {"CP280", "CP280"},
  {"CP284", "CP284"},
  {"CP285", "CP285"},
  {"CP297", "CP297"},
  {"CP423", "CP423"},
  {"CP424", "CP424"},
  {"CP500", "CP500"},
  {"CP905", "CP905"},
  {"CP1026", "CP1026"},
  # Phase 5: ASCII-superset single-byte
  {"CP856", "CP856"},
  {"CP922", "CP922"},
  {"CP853", "CP853"},
  {"CP1046", "CP1046"},
  {"CP1124", "CP1124"},
  {"CP1125", "CP1125"},
  {"CP1129", "CP1129"},
  {"CP1131", "CP1131"},
  {"CP1133", "CP1133"},
  {"CP1161", "CP1161"},
  {"CP1162", "CP1162"},
  {"CP1163", "CP1163"},
  {"ATARIST", "ATARIST"},
  {"KZ_1048", "KZ-1048"},
  {"MULELAO_1", "MULELAO-1"},
  {"RISCOS_LATIN1", "RISCOS-LATIN1"},
  # Phase 5: Non-ASCII non-EBCDIC
  {"TCVN", "TCVN"},
}

struct EncodingData
  property decode_table : Array(UInt16)   # 256 entries, full byte range
  property encode_pairs : Array({UInt16, UInt8})
  property is_ascii_superset : Bool

  def initialize
    @decode_table = Array(UInt16).new(256, 0xFFFF_u16)
    @encode_pairs = [] of {UInt16, UInt8}
    @is_ascii_superset = true
  end
end

def iconv_convert_one(cd : LibC::IconvT, input : Bytes, output : Bytes) : Int32
  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = output.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(output.size)

  # Reset state
  LibC.iconv(cd, Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null,
             Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))

  if result == ~LibC::SizeT.new(0) || in_left != 0
    -1
  else
    (output.size - out_left).to_i32
  end
end

def probe_encoding(iconv_name : String) : EncodingData
  data = EncodingData.new

  # Phase 1: Probe decode direction (encoding → UTF-32LE)
  cd_decode = LibC.iconv_open("UTF-32LE", iconv_name)
  if cd_decode.address == ~LibC::SizeT.new(0)
    STDERR.puts "WARNING: iconv_open failed for decode #{iconv_name}"
    return data
  end

  (0x00..0xFF).each do |byte_val|
    output = Bytes.new(16)
    written = iconv_convert_one(cd_decode, Bytes[byte_val.to_u8], output)

    if written < 4
      data.decode_table[byte_val] = 0xFFFF_u16
      if byte_val < 0x80
        data.is_ascii_superset = false
      end
    else
      cp = (output[0].to_u32) | (output[1].to_u32 << 8) | (output[2].to_u32 << 16) | (output[3].to_u32 << 24)
      if written > 4
        STDERR.puts "WARNING: #{iconv_name} byte 0x#{byte_val.to_s(16).rjust(2, '0')} produces #{written // 4} codepoints (using first: U+#{cp.to_s(16).upcase})"
      end
      if cp <= 0xFFFF
        data.decode_table[byte_val] = cp.to_u16
        if byte_val < 0x80 && cp != byte_val.to_u32
          data.is_ascii_superset = false
        end
      else
        STDERR.puts "WARNING: #{iconv_name} byte 0x#{byte_val.to_s(16).rjust(2, '0')} maps to U+#{cp.to_s(16).upcase} (outside BMP)"
        data.decode_table[byte_val] = 0xFFFF_u16
      end
    end
  end

  LibC.iconv_close(cd_decode)

  # Phase 2: Probe encode direction (UTF-8 → encoding)
  # For each codepoint in the decode table, ask system iconv what byte it produces
  cd_encode = LibC.iconv_open(iconv_name, "UTF-8")
  if cd_encode.address == ~LibC::SizeT.new(0)
    STDERR.puts "WARNING: iconv_open failed for encode #{iconv_name}"
    return data
  end

  # Collect all unique codepoints from decode table + ASCII/Latin-1 range
  codepoints_seen = Set(UInt16).new
  data.decode_table.each { |cp| codepoints_seen << cp if cp != 0xFFFF_u16 }
  # Always probe ASCII and Latin-1 range for encode (handles asymmetric mappings like TCVN)
  (1_u16..0xFF_u16).each { |cp| codepoints_seen << cp }

  codepoints_seen.each do |cp|
    # Encode codepoint to UTF-8
    utf8 = IO::Memory.new(4)
    if cp < 0x80
      utf8.write_byte(cp.to_u8)
    elsif cp < 0x800
      utf8.write_byte((0xC0 | (cp >> 6)).to_u8)
      utf8.write_byte((0x80 | (cp & 0x3F)).to_u8)
    else
      utf8.write_byte((0xE0 | (cp >> 12)).to_u8)
      utf8.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_u8)
      utf8.write_byte((0x80 | (cp & 0x3F)).to_u8)
    end

    output = Bytes.new(4)
    written = iconv_convert_one(cd_encode, utf8.to_slice, output)

    if written == 1
      byte = output[0]
      # Include mapping if it won't be created by decode table inversion
      if cp.to_u16 != byte.to_u16 || data.decode_table[byte.to_i32] != cp.to_u16
        data.encode_pairs << {cp.to_u16, byte}
      end
    end
  end

  LibC.iconv_close(cd_encode)

  data.encode_pairs.sort_by! { |cp, _| cp }
  # Deduplicate (keep first occurrence since they're sorted by codepoint)
  data.encode_pairs.uniq! { |cp, _| cp }

  data
end

# Main
io = IO::Memory.new

io.puts "# AUTO-GENERATED by tools/generate_tables.cr — DO NOT EDIT"
io.puts "# Generated from system iconv on #{`sw_vers -productName`.strip} #{`sw_vers -productVersion`.strip}"
io.puts "#"
io.puts "# Each DECODE table is 256 entries mapping byte 0x00-0xFF to Unicode codepoints."
io.puts "# 0xFFFF = undefined (ILSEQ)."
io.puts "# Each ENCODE_PAIRS array lists {codepoint, byte} from system iconv's encode direction."
io.puts ""
io.puts "module Iconvcr::Tables::SingleByte"

non_ascii_supersets = [] of String

ENCODINGS.each do |crystal_name, iconv_name|
  data = probe_encoding(iconv_name)
  non_ascii_supersets << iconv_name unless data.is_ascii_superset

  io.puts ""
  io.puts "  # #{iconv_name}#{data.is_ascii_superset ? "" : " (NOT ASCII superset)"}"
  io.print "  #{crystal_name}_DECODE = StaticArray(UInt16, 256).new { |i| {"
  data.decode_table.each_with_index do |cp, i|
    io.print ", " if i > 0
    io.print "0x#{cp.to_s(16).upcase.rjust(4, '0')}_u16"
  end
  io.puts "}[i] }"

  io.print "  #{crystal_name}_ENCODE_PAIRS = ["
  data.encode_pairs.each_with_index do |(cp, byte), i|
    io.print ", " if i > 0
    io.print "{0x#{cp.to_s(16).upcase.rjust(4, '0')}_u16, 0x#{byte.to_s(16).upcase.rjust(2, '0')}_u8}"
  end
  io.puts "]"
end

io.puts "end"

output_path = File.join(__DIR__, "..", "src", "iconvcr", "tables", "single_byte.cr")
File.write(output_path, io.to_s)

puts "Generated #{output_path}"
puts "Non-ASCII supersets: #{non_ascii_supersets}" unless non_ascii_supersets.empty?
puts "Done! #{ENCODINGS.size} encodings processed."
