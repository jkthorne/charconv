#!/usr/bin/env crystal

# Generates CJK encoding tables by probing system iconv.
# For each CJK charset, probes all valid (lead, trail) byte pairs for decode,
# and all BMP codepoints for encode.
#
# Output files:
#   src/charconv/tables/cjk_jis.cr    — JIS X 0208, JIS X 0212, JIS X 0201
#   src/charconv/tables/cjk_gb.cr     — GB2312, GBK ranges
#   src/charconv/tables/cjk_big5.cr   — Big5, Big5-HKSCS, CP950 extensions
#   src/charconv/tables/cjk_ksc.cr    — KSC 5601, CP949 extensions

# -----------------------------------------------------------------------
# CJK charset definitions: each defines the byte ranges to probe
# -----------------------------------------------------------------------

struct CJKCharset
  property crystal_name : String
  property iconv_name : String
  property lead_range : Range(Int32, Int32)
  property trail_range : Range(Int32, Int32)
  property has_single_byte_extra : Bool  # e.g., half-width katakana in Shift_JIS

  def initialize(@crystal_name, @iconv_name, @lead_range, @trail_range, @has_single_byte_extra = false)
  end
end

# -----------------------------------------------------------------------
# Table data structures
# -----------------------------------------------------------------------

struct CJKTableData
  property decode_table : Array(UInt16)  # flat 2D: [lead_off * trail_count + trail_off]
  property lead_min : Int32
  property lead_max : Int32
  property trail_min : Int32
  property trail_max : Int32
  # Encode: two-level page table
  property encode_summary : Array(UInt16)  # 256 entries: page index per high byte
  property encode_pages : Array(Array(UInt16))  # each page is 256 entries
  # Single-byte extras (e.g., half-width katakana 0xA1-0xDF in Shift_JIS)
  property single_decode : Array(UInt16)  # 256 entries for single-byte range
  property single_encode_pairs : Array({UInt16, UInt8})

  def initialize
    @decode_table = [] of UInt16
    @lead_min = 0
    @lead_max = 0
    @trail_min = 0
    @trail_max = 0
    @encode_summary = Array(UInt16).new(256, 0xFFFF_u16)
    @encode_pages = [] of Array(UInt16)
    @single_decode = Array(UInt16).new(256, 0xFFFF_u16)
    @single_encode_pairs = [] of {UInt16, UInt8}
  end

  def trail_count
    trail_max - trail_min + 1
  end
end

# -----------------------------------------------------------------------
# iconv helpers
# -----------------------------------------------------------------------

def iconv_convert(cd : LibC::IconvT, input : Bytes, output : Bytes) : Int32
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

def codepoint_to_utf8(cp : UInt32) : Bytes
  buf = IO::Memory.new(4)
  if cp < 0x80
    buf.write_byte(cp.to_u8)
  elsif cp < 0x800
    buf.write_byte((0xC0 | (cp >> 6)).to_u8)
    buf.write_byte((0x80 | (cp & 0x3F)).to_u8)
  elsif cp < 0x10000
    buf.write_byte((0xE0 | (cp >> 12)).to_u8)
    buf.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_u8)
    buf.write_byte((0x80 | (cp & 0x3F)).to_u8)
  else
    buf.write_byte((0xF0 | (cp >> 18)).to_u8)
    buf.write_byte((0x80 | ((cp >> 12) & 0x3F)).to_u8)
    buf.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_u8)
    buf.write_byte((0x80 | (cp & 0x3F)).to_u8)
  end
  buf.to_slice
end

# -----------------------------------------------------------------------
# Probing
# -----------------------------------------------------------------------

def probe_cjk_charset(charset : CJKCharset) : CJKTableData
  data = CJKTableData.new
  data.lead_min = charset.lead_range.begin
  data.lead_max = charset.lead_range.end
  data.trail_min = charset.trail_range.begin
  data.trail_max = charset.trail_range.end

  lead_count = data.lead_max - data.lead_min + 1
  trail_count = data.trail_count
  data.decode_table = Array(UInt16).new(lead_count * trail_count, 0xFFFF_u16)

  # Open iconv handles
  cd_decode = LibC.iconv_open("UTF-32LE", charset.iconv_name)
  if cd_decode.address == ~LibC::SizeT.new(0)
    STDERR.puts "ERROR: iconv_open failed for decode #{charset.iconv_name}"
    return data
  end

  cd_encode = LibC.iconv_open(charset.iconv_name, "UTF-8")
  if cd_encode.address == ~LibC::SizeT.new(0)
    STDERR.puts "ERROR: iconv_open failed for encode #{charset.iconv_name}"
    LibC.iconv_close(cd_decode)
    return data
  end

  # --- Probe decode: all (lead, trail) pairs ---
  mapped = 0
  output = Bytes.new(16)

  charset.lead_range.each do |lead|
    charset.trail_range.each do |trail|
      input = Bytes[lead.to_u8, trail.to_u8]
      written = iconv_convert(cd_decode, input, output)

      if written >= 4
        cp = output[0].to_u32 | (output[1].to_u32 << 8) | (output[2].to_u32 << 16) | (output[3].to_u32 << 24)
        if cp <= 0xFFFF
          idx = (lead - data.lead_min) * trail_count + (trail - data.trail_min)
          data.decode_table[idx] = cp.to_u16
          mapped += 1
        end
      end
    end
  end

  # --- Probe single-byte extras (e.g., half-width katakana, yen sign) ---
  if charset.has_single_byte_extra
    (0x00..0xFF).each do |byte_val|
      input = Bytes[byte_val.to_u8]
      written = iconv_convert(cd_decode, input, output)
      if written >= 4
        cp = output[0].to_u32 | (output[1].to_u32 << 8) | (output[2].to_u32 << 16) | (output[3].to_u32 << 24)
        data.single_decode[byte_val] = cp.to_u16 if cp <= 0xFFFF
      end
    end
  end

  # --- Probe encode: all BMP codepoints ---
  # Build a flat encode map first, then convert to page table
  encode_flat = Hash(UInt16, UInt16).new  # codepoint → encoded 2-byte value

  (0x0080_u32..0xFFFF_u32).each do |cp|
    next if cp >= 0xD800 && cp <= 0xDFFF  # skip surrogates

    utf8 = codepoint_to_utf8(cp)
    enc_output = Bytes.new(8)
    written = iconv_convert(cd_encode, utf8, enc_output)

    if written == 2
      encoded = enc_output[0].to_u16 << 8 | enc_output[1].to_u16
      encode_flat[cp.to_u16] = encoded
    elsif written == 1 && charset.has_single_byte_extra
      # Single-byte encode result
      data.single_encode_pairs << {cp.to_u16, enc_output[0]}
    end
  end

  # Build two-level page table from encode_flat
  # Summary: 256 entries, one per high byte of codepoint
  # Pages: variable, each 256 entries for low byte
  pages = [] of Array(UInt16)
  empty_page = Array(UInt16).new(256, 0_u16)

  (0..255).each do |high|
    page = Array(UInt16).new(256, 0_u16)
    has_entries = false
    (0..255).each do |low|
      cp = ((high << 8) | low).to_u16
      if val = encode_flat[cp]?
        page[low] = val
        has_entries = true
      end
    end

    if has_entries
      # Check if this page already exists (dedup)
      existing_idx = pages.index(page)
      if existing_idx
        data.encode_summary[high] = existing_idx.to_u16
      else
        data.encode_summary[high] = pages.size.to_u16
        pages << page
      end
    end
    # else leave summary[high] = 0xFFFF (no entries)
  end
  data.encode_pages = pages

  LibC.iconv_close(cd_decode)
  LibC.iconv_close(cd_encode)

  puts "  #{charset.iconv_name}: #{mapped} decode mappings, #{encode_flat.size} encode mappings, #{pages.size} encode pages"
  data
end

# -----------------------------------------------------------------------
# Code generation helpers
# -----------------------------------------------------------------------

def emit_decode_table(io : IO, name : String, data : CJKTableData)
  lead_count = data.lead_max - data.lead_min + 1
  trail_count = data.trail_count
  total = lead_count * trail_count

  io.puts "  # #{name}: lead 0x#{data.lead_min.to_s(16).upcase}-0x#{data.lead_max.to_s(16).upcase}, trail 0x#{data.trail_min.to_s(16).upcase}-0x#{data.trail_max.to_s(16).upcase}"
  io.puts "  #{name}_LEAD_MIN = 0x#{data.lead_min.to_s(16).upcase}"
  io.puts "  #{name}_LEAD_MAX = 0x#{data.lead_max.to_s(16).upcase}"
  io.puts "  #{name}_TRAIL_MIN = 0x#{data.trail_min.to_s(16).upcase}"
  io.puts "  #{name}_TRAIL_MAX = 0x#{data.trail_max.to_s(16).upcase}"
  io.puts "  #{name}_TRAIL_COUNT = #{trail_count}"

  # Emit decode table as Slice from Array (avoids Crystal's 300-element tuple limit)
  io.print "  #{name}_DECODE = Slice(UInt16).new(#{total}, 0xFFFF_u16).tap { |s| ["
  col = 0
  data.decode_table.each_with_index do |cp, i|
    next if cp == 0xFFFF_u16
    io.print ", " if col > 0
    if col > 0 && col % 8 == 0
      io.puts
      io.print "    "
    end
    io.print "{#{i}, 0x#{cp.to_s(16).upcase.rjust(4, '0')}_u16}"
    col += 1
  end
  io.puts "].each { |(i, v)| s[i] = v } }"
end

def emit_encode_pages(io : IO, name : String, data : CJKTableData)
  # Summary: 256 entries, each is a page index (0xFFFF = no page)
  io.print "  #{name}_ENCODE_SUMMARY = Slice(UInt16).new(256, 0xFFFF_u16).tap { |s| ["
  col = 0
  data.encode_summary.each_with_index do |val, i|
    next if val == 0xFFFF_u16
    io.print ", " if col > 0
    io.print "{#{i}, 0x#{val.to_s(16).upcase.rjust(4, '0')}_u16}"
    col += 1
  end
  io.puts "].each { |(i, v)| s[i] = v } }"

  # Each page: 256 entries, codepoint low byte → encoded 2-byte value
  data.encode_pages.each_with_index do |page, pi|
    io.print "  #{name}_ENCODE_PAGE_#{pi} = Slice(UInt16).new(256, 0_u16).tap { |s| ["
    col = 0
    page.each_with_index do |val, i|
      next if val == 0_u16
      io.print ", " if col > 0
      if col > 0 && col % 8 == 0
        io.puts
        io.print "    "
      end
      io.print "{#{i}, 0x#{val.to_s(16).upcase.rjust(4, '0')}_u16}"
      col += 1
    end
    io.puts "].each { |(i, v)| s[i] = v } }"
  end

  io.puts "  #{name}_ENCODE_PAGES = ["
  data.encode_pages.size.times do |i|
    io.print "    #{name}_ENCODE_PAGE_#{i},"
    io.puts
  end
  io.puts "  ]"
end

def emit_single_byte_extras(io : IO, name : String, data : CJKTableData)
  return unless data.single_decode.any? { |cp| cp != 0xFFFF_u16 }

  io.print "  #{name}_SINGLE_DECODE = Slice(UInt16).new(256, 0xFFFF_u16).tap { |s| ["
  col = 0
  data.single_decode.each_with_index do |cp, i|
    next if cp == 0xFFFF_u16
    io.print ", " if col > 0
    io.print "{#{i}, 0x#{cp.to_s(16).upcase.rjust(4, '0')}_u16}"
    col += 1
  end
  io.puts "].each { |(i, v)| s[i] = v } }"

  if data.single_encode_pairs.size > 0
    io.print "  #{name}_SINGLE_ENCODE_PAIRS = ["
    data.single_encode_pairs.each_with_index do |(cp, byte), i|
      io.print ", " if i > 0
      io.print "{0x#{cp.to_s(16).upcase.rjust(4, '0')}_u16, 0x#{byte.to_s(16).upcase.rjust(2, '0')}_u8}"
    end
    io.puts "]"
  end
end

def write_table_file(path : String, module_name : String, charsets : Array(CJKCharset))
  io = IO::Memory.new

  io.puts "# AUTO-GENERATED by tools/generate_cjk_tables.cr — DO NOT EDIT"
  io.puts "# Generated from system iconv on #{`sw_vers -productName`.strip} #{`sw_vers -productVersion`.strip}"
  io.puts ""
  io.puts "module CharConv::Tables::#{module_name}"

  charsets.each do |charset|
    puts "Probing #{charset.iconv_name}..."
    data = probe_cjk_charset(charset)
    io.puts ""
    emit_decode_table(io, charset.crystal_name, data)
    emit_encode_pages(io, charset.crystal_name, data)
    emit_single_byte_extras(io, charset.crystal_name, data)
  end

  io.puts "end"

  File.write(path, io.to_s)
  puts "Written: #{path}"
end

# -----------------------------------------------------------------------
# Charset definitions
# -----------------------------------------------------------------------

JIS_CHARSETS = [
  # JIS X 0208 (used by EUC-JP with 0xA1-0xFE range and Shift_JIS with remapping)
  # We probe via EUC-JP which uses lead 0xA1-0xFE, trail 0xA1-0xFE for JIS X 0208
  CJKCharset.new("EUCJP", "EUC-JP", 0xA1..0xFE, 0xA1..0xFE, has_single_byte_extra: true),

  # Shift_JIS: lead 0x81-0x9F,0xE0-0xEF, trail 0x40-0xFC
  # We probe the full contiguous range and accept 0xFFFF for gaps
  CJKCharset.new("SHIFTJIS", "SHIFT_JIS", 0x81..0xEF, 0x40..0xFC, has_single_byte_extra: true),

  # CP932 (Microsoft Shift_JIS superset): lead 0x81-0xFC
  CJKCharset.new("CP932", "CP932", 0x81..0xFC, 0x40..0xFC, has_single_byte_extra: true),
]

GB_CHARSETS = [
  # GBK: lead 0x81-0xFE, trail 0x40-0xFE (gap at 0x7F handled by 0xFFFF)
  CJKCharset.new("GBK", "GBK", 0x81..0xFE, 0x40..0xFE),

  # GB2312 via EUC-CN: lead 0xA1-0xF7, trail 0xA1-0xFE
  CJKCharset.new("EUCCN", "EUC-CN", 0xA1..0xF7, 0xA1..0xFE),
]

BIG5_CHARSETS = [
  # Big5: lead 0xA1-0xF9, trail 0x40-0xFE
  CJKCharset.new("BIG5", "BIG5", 0x81..0xFE, 0x40..0xFE),

  # CP950: same range as Big5 but with Microsoft extensions
  CJKCharset.new("CP950", "CP950", 0x81..0xFE, 0x40..0xFE),

  # Big5-HKSCS: extends Big5 with Hong Kong additions
  CJKCharset.new("BIG5HKSCS", "BIG5-HKSCS", 0x81..0xFE, 0x40..0xFE),
]

KSC_CHARSETS = [
  # EUC-KR: lead 0xA1-0xFE, trail 0xA1-0xFE (KSC 5601)
  CJKCharset.new("EUCKR", "EUC-KR", 0xA1..0xFE, 0xA1..0xFE),

  # CP949/UHC: extends EUC-KR with lead 0x81-0xFE, trail 0x41-0xFE
  CJKCharset.new("CP949", "CP949", 0x81..0xFE, 0x41..0xFE),

  # JOHAB: lead 0x84-0xD3,0xD8-0xDE,0xE0-0xF9, trail 0x31-0x7E,0x91-0xFE
  # Probe full range, accept 0xFFFF for invalid pairs
  CJKCharset.new("JOHAB", "JOHAB", 0x84..0xF9, 0x31..0xFE),
]

# EUC-TW uses plane indicators: 0x8EA1-0x8EAF + 2 more bytes
# We probe it separately since it has a 4-byte form
EUCTW_CHARSETS = [
  # EUC-TW plane 1: lead 0xA1-0xFE, trail 0xA1-0xFE (CNS 11643 plane 1)
  CJKCharset.new("EUCTW", "EUC-TW", 0xA1..0xFE, 0xA1..0xFE),
]

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

base = File.join(__DIR__, "..", "src", "charconv", "tables")

puts "=== Generating JIS tables ==="
write_table_file(File.join(base, "cjk_jis.cr"), "CJKJis", JIS_CHARSETS)

puts "\n=== Generating GB tables ==="
write_table_file(File.join(base, "cjk_gb.cr"), "CJKGB", GB_CHARSETS)

puts "\n=== Generating Big5 tables ==="
write_table_file(File.join(base, "cjk_big5.cr"), "CJKBig5", BIG5_CHARSETS)

puts "\n=== Generating KSC tables ==="
write_table_file(File.join(base, "cjk_ksc.cr"), "CJKKSC", KSC_CHARSETS)

puts "\n=== Generating EUC-TW tables ==="
write_table_file(File.join(base, "cjk_euctw.cr"), "CJKEUCTW", EUCTW_CHARSETS)

puts "\nDone!"
