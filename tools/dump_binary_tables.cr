# Dumps all CJK and single-byte lookup tables to compact binary files.
# Run once: crystal run tools/dump_binary_tables.cr
# Output: src/charconv/tables/data/*.bin

require "../src/charconv/tables/cjk_big5"
require "../src/charconv/tables/cjk_ksc"
require "../src/charconv/tables/cjk_jis"
require "../src/charconv/tables/cjk_gb"
require "../src/charconv/tables/cjk_euctw"
require "../src/charconv/tables/single_byte"

OUT = "src/charconv/tables/data"
Dir.mkdir_p(OUT)

def write_u16(path : String, slice : Slice(UInt16))
  File.open(path, "wb") do |f|
    f.write(Slice.new(slice.to_unsafe.as(Pointer(UInt8)), slice.size * 2))
  end
  puts "  #{path} (#{slice.size} entries, #{slice.size * 2} bytes)"
end

def write_u16_pages(path : String, pages : Array(Slice(UInt16)))
  File.open(path, "wb") do |f|
    pages.each do |page|
      f.write(Slice.new(page.to_unsafe.as(Pointer(UInt8)), page.size * 2))
    end
  end
  total = pages.sum(&.size)
  puts "  #{path} (#{pages.size} pages, #{total} entries, #{total * 2} bytes)"
end

def write_static_array_u16(path : String, arr : StaticArray(UInt16, 256))
  File.open(path, "wb") do |f|
    f.write(Slice.new(arr.to_unsafe.as(Pointer(UInt8)), 512))
  end
end

macro dump_cjk(mod, prefix, lc)
  puts "--- {{prefix}} ---"
  write_u16("#{OUT}/{{lc.id}}_decode.bin", {{mod}}::{{prefix}}_DECODE)
  write_u16("#{OUT}/{{lc.id}}_encode_summary.bin", {{mod}}::{{prefix}}_ENCODE_SUMMARY)
  write_u16_pages("#{OUT}/{{lc.id}}_encode_pages.bin", {{mod}}::{{prefix}}_ENCODE_PAGES)
end

include CharConv::Tables

# Big5 family
dump_cjk(CJKBig5, BIG5, "big5")
dump_cjk(CJKBig5, CP950, "cp950")
dump_cjk(CJKBig5, BIG5HKSCS, "big5hkscs")

# Korean family
dump_cjk(CJKKSC, EUCKR, "euckr")
dump_cjk(CJKKSC, CP949, "cp949")
dump_cjk(CJKKSC, JOHAB, "johab")

# Japanese family
dump_cjk(CJKJis, EUCJP, "eucjp")
dump_cjk(CJKJis, SHIFTJIS, "shiftjis")
dump_cjk(CJKJis, CP932, "cp932")

# Chinese family
dump_cjk(CJKGB, GBK, "gbk")
dump_cjk(CJKGB, EUCCN, "euccn")

# Taiwan
dump_cjk(CJKEUCTW, EUCTW, "euctw")

# CP932 single-byte decode
puts "--- CP932_SINGLE ---"
write_u16("#{OUT}/cp932_single_decode.bin", CJKJis::CP932_SINGLE_DECODE)

# Single-byte codecs (64 encodings × 256 entries = 32KB)
puts "--- Single-byte DECODE tables ---"
{% for enc in %w[
  ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
  ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
  ISO_8859_15 ISO_8859_16
  CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
  KOI8_R KOI8_U KOI8_RU
  MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
  MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
  CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
  CP864 CP865 CP866 CP869
  CP874 TIS_620 VISCII ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
  NEXTSTEP PT154 KOI8_T
  CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
  CP423 CP424 CP500 CP905 CP1026
  CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
  CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1
  TCVN
] %}
  write_static_array_u16("#{OUT}/sb_{{ enc.downcase.id }}_decode.bin", SingleByte::{{ enc.id }}_DECODE)
{% end %}
puts "Done."

# Also dump all single-byte encode pairs as binary: [count:u16][cp:u16, byte:u8, pad:u8]...
puts "--- Single-byte ENCODE_PAIRS ---"
{% for enc in %w[
  ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
  ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
  ISO_8859_15 ISO_8859_16
  CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
  KOI8_R KOI8_U KOI8_RU
  MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
  MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
  CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
  CP864 CP865 CP866 CP869
  CP874 TIS_620 VISCII ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
  NEXTSTEP PT154 KOI8_T
  CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
  CP423 CP424 CP500 CP905 CP1026
  CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
  CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1
  TCVN
] %}
  pairs = SingleByte::{{ enc.id }}_ENCODE_PAIRS
  File.open("#{OUT}/sb_{{ enc.downcase.id }}_encode_pairs.bin", "wb") do |f|
    pairs.each do |cp, byte|
      f.write_bytes(cp, IO::ByteFormat::LittleEndian)
      f.write_byte(byte)
    end
  end
{% end %}
puts "Done."
