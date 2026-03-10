# Generates transliteration lookup table from Unicode NFKD decomposition data
# and manual mappings for symbols, ligatures, etc.
#
# Usage: crystal run tools/generate_translit.cr > src/iconvcr/transliteration.cr

# Manual mappings: {codepoint, replacement_string}
# These override or supplement NFKD decomposition
MANUAL_MAPPINGS = {
  # Ligatures
  0x00C6 => "AE",  # Æ
  0x00E6 => "ae",  # æ
  0x0132 => "IJ",  # Ĳ
  0x0133 => "ij",  # ĳ
  0x0152 => "OE",  # Œ
  0x0153 => "oe",  # œ
  0x1E9E => "SS",  # ẞ (capital sharp s)
  0x00DF => "ss",  # ß
  0xFB00 => "ff",  # ﬀ
  0xFB01 => "fi",  # ﬁ
  0xFB02 => "fl",  # ﬂ
  0xFB03 => "ffi", # ﬃ
  0xFB04 => "ffl", # ﬄ
  0xFB05 => "st",  # ﬅ
  0xFB06 => "st",  # ﬆ

  # Symbols
  0x00A9 => "(c)",   # ©
  0x00AE => "(R)",   # ®
  0x2122 => "(TM)",  # ™
  0x00B1 => "+/-",   # ±
  0x00D7 => "x",     # ×
  0x00F7 => "/",     # ÷
  0x2026 => "...",   # …
  0x2022 => "*",     # •
  0x00B7 => ".",     # ·
  0x2219 => ".",     # ∙
  0x00AC => "!",     # ¬
  0x00A6 => "|",     # ¦
  0x00B6 => "P",     # ¶
  0x00A7 => "S",     # §
  0x2020 => "+",     # †
  0x2021 => "++",    # ‡
  0x00B0 => "o",     # °
  0x2032 => "'",     # ′
  0x2033 => "''",    # ″
  0x2034 => "'''",   # ‴
  0x00AB => "<<",    # «
  0x00BB => ">>",    # »
  0x2039 => "<",     # ‹
  0x203A => ">",     # ›

  # Quotation marks
  0x2018 => "'",  # '
  0x2019 => "'",  # '
  0x201A => ",",  # ‚
  0x201B => "'",  # ‛
  0x201C => "\"", # "
  0x201D => "\"", # "
  0x201E => ",,", # „
  0x201F => "\"", # ‟

  # Dashes
  0x2010 => "-",  # ‐
  0x2011 => "-",  # ‑
  0x2012 => "-",  # ‒
  0x2013 => "-",  # –
  0x2014 => "--", # —
  0x2015 => "--", # ―

  # Spaces
  0x00A0 => " ",  # non-breaking space
  0x2002 => " ",  # en space
  0x2003 => " ",  # em space
  0x2004 => " ",  # three-per-em space
  0x2005 => " ",  # four-per-em space
  0x2006 => " ",  # six-per-em space
  0x2007 => " ",  # figure space
  0x2008 => " ",  # punctuation space
  0x2009 => " ",  # thin space
  0x200A => " ",  # hair space
  0x202F => " ",  # narrow no-break space
  0x205F => " ",  # medium mathematical space

  # Fractions
  0x00BC => "1/4", # ¼
  0x00BD => "1/2", # ½
  0x00BE => "3/4", # ¾
  0x2153 => "1/3", # ⅓
  0x2154 => "2/3", # ⅔
  0x2155 => "1/5", # ⅕
  0x2156 => "2/5", # ⅖
  0x2157 => "3/5", # ⅗
  0x2158 => "4/5", # ⅘
  0x2159 => "1/6", # ⅙
  0x215A => "5/6", # ⅚
  0x215B => "1/8", # ⅛
  0x215C => "3/8", # ⅜
  0x215D => "5/8", # ⅝
  0x215E => "7/8", # ⅞

  # Superscripts
  0x00B2 => "2",  # ²
  0x00B3 => "3",  # ³
  0x00B9 => "1",  # ¹
  0x2070 => "0",  # ⁰
  0x2074 => "4",  # ⁴
  0x2075 => "5",  # ⁵
  0x2076 => "6",  # ⁶
  0x2077 => "7",  # ⁷
  0x2078 => "8",  # ⁸
  0x2079 => "9",  # ⁹
  0x207A => "+",  # ⁺
  0x207B => "-",  # ⁻
  0x207C => "=",  # ⁼
  0x207D => "(",  # ⁽
  0x207E => ")",  # ⁾
  0x207F => "n",  # ⁿ

  # Subscripts
  0x2080 => "0",  # ₀
  0x2081 => "1",  # ₁
  0x2082 => "2",  # ₂
  0x2083 => "3",  # ₃
  0x2084 => "4",  # ₄
  0x2085 => "5",  # ₅
  0x2086 => "6",  # ₆
  0x2087 => "7",  # ₇
  0x2088 => "8",  # ₈
  0x2089 => "9",  # ₉
  0x208A => "+",  # ₊
  0x208B => "-",  # ₋
  0x208C => "=",  # ₌
  0x208D => "(",  # ₍
  0x208E => ")",  # ₎

  # Currency
  0x20AC => "EUR",  # €
  0x00A2 => "c",    # ¢
  0x00A3 => "GBP",  # £
  0x00A5 => "JPY",  # ¥
  0x20A3 => "F",    # ₣
  0x20A4 => "L",    # ₤
  0x20A7 => "Pts",  # ₧
  0x20A9 => "W",    # ₩
  0x20AA => "NIS",  # ₪
  0x20AB => "d",    # ₫
  0x20B9 => "Rs",   # ₹
  0x20BD => "P",    # ₽
  0x20BF => "BTC",  # ₿

  # Arrows
  0x2190 => "<-",   # ←
  0x2192 => "->",   # →
  0x2194 => "<->",  # ↔
  0x21D0 => "<=",   # ⇐
  0x21D2 => "=>",   # ⇒
  0x21D4 => "<=>",  # ⇔

  # Mathematical
  0x2260 => "!=",   # ≠
  0x2264 => "<=",   # ≤
  0x2265 => ">=",   # ≥
  0x2248 => "~=",   # ≈
  0x221E => "inf",  # ∞
  0x00B5 => "u",    # µ (micro sign)

  # Misc symbols
  0x2116 => "No",   # №
  0x2103 => "oC",   # ℃
  0x2109 => "oF",   # ℉
  0x212A => "K",    # K (kelvin)
  0x2126 => "Ohm",  # Ω

  # Latin extensions — Eth, Thorn, etc.
  0x00D0 => "D",  # Ð
  0x00F0 => "d",  # ð
  0x00DE => "Th", # Þ
  0x00FE => "th", # þ
  0x0110 => "D",  # Đ
  0x0111 => "d",  # đ
  0x0126 => "H",  # Ħ
  0x0127 => "h",  # ħ
  0x0131 => "i",  # ı (dotless i)
  0x0138 => "k",  # ĸ (kra)
  0x0141 => "L",  # Ł
  0x0142 => "l",  # ł
  0x014A => "N",  # Ŋ
  0x014B => "n",  # ŋ
  0x0166 => "T",  # Ŧ
  0x0167 => "t",  # ŧ
}

# Unicode combining character categories (marks to strip for accent removal)
# Range: 0x0300-0x036F (Combining Diacritical Marks)
def combining_mark?(cp : Int32) : Bool
  (0x0300 <= cp <= 0x036F) ||  # Combining Diacritical Marks
  (0x1AB0 <= cp <= 0x1AFF) ||  # Combining Diacritical Marks Extended
  (0x1DC0 <= cp <= 0x1DFF) ||  # Combining Diacritical Marks Supplement
  (0x20D0 <= cp <= 0x20FF) ||  # Combining Diacritical Marks for Symbols
  (0xFE20 <= cp <= 0xFE2F)     # Combining Half Marks
end

# Read Unicode decomposition data from system
# We'll generate NFD decompositions for Latin characters with diacritics
def generate_nfd_mappings : Hash(Int32, String)
  mappings = Hash(Int32, String).new

  # Use Crystal's built-in Unicode normalization to get NFD base characters
  # For characters in Latin Extended blocks, decompose and strip combining marks
  ranges = [
    (0x00C0..0x024F),   # Latin Extended-A, Latin Extended-B
    (0x1E00..0x1EFF),   # Latin Extended Additional
    (0x0370..0x03FF),   # Greek and Coptic (for things like ά→α)
    (0x0400..0x04FF),   # Cyrillic (for things like й→и)
  ]

  ranges.each do |range|
    range.each do |cp|
      char = cp.chr.to_s
      nfd = char.unicode_normalize(:nfd)
      next if nfd.size <= 1 # No decomposition or single char

      # Extract base characters (non-combining)
      base = String.build do |io|
        nfd.each_char do |c|
          io << c unless combining_mark?(c.ord)
        end
      end

      # Only keep if base is pure ASCII
      next if base.empty?
      next if base == char
      next unless base.each_char.all? { |c| c.ascii? }

      mappings[cp] = base
    end
  end

  mappings
end

# Build final sorted table
nfd = generate_nfd_mappings
all_mappings = Hash(Int32, String).new

# Add NFD-derived mappings first
nfd.each { |cp, s| all_mappings[cp] = s }

# Manual mappings override NFD
MANUAL_MAPPINGS.each { |cp, s| all_mappings[cp] = s }

# Sort by codepoint
sorted = all_mappings.to_a.sort_by(&.[0])

# Generate Crystal source
puts "# Auto-generated transliteration table"
puts "# Generated by tools/generate_translit.cr"
puts "# #{sorted.size} entries"
puts "#"
puts "# Each entry: {codepoint, {replacement_codepoints...}} with 0-padding"
puts "# Binary search for O(log n) lookup"
puts ""
puts "module Iconvcr::Transliteration"
puts "  # Max replacement length (in codepoints)"
puts "  MAX_REPL = 4"
puts ""
puts "  # {source_codepoint, {repl_cp1, repl_cp2, repl_cp3, repl_cp4}}"
puts "  # 0 = end-of-replacement sentinel"
puts "  TABLE = ["

sorted.each do |cp, repl|
  cps = repl.chars.map(&.ord.to_u32)
  # Pad to 4 with zeros
  while cps.size < 4
    cps << 0_u32
  end
  if cps.size > 4
    STDERR.puts "WARNING: replacement for U+#{cp.to_s(16).upcase.rjust(4, '0')} is #{cps.size} codepoints, truncating to 4"
    cps = cps[0, 4]
  end
  desc = repl.gsub("\\", "\\\\").gsub("\"", "\\\"")
  puts "    {0x#{cp.to_s(16).upcase.rjust(4, '0')}_u32, StaticArray[#{cps.map { |c| "0x#{c.to_s(16).upcase.rjust(4, '0')}_u32" }.join(", ")}]}, # #{cp.chr} → \"#{desc}\""
end

puts "  ]"
puts ""
puts "  # Binary search for a codepoint in the sorted table."
puts "  # Returns the replacement codepoints (StaticArray with 0-termination) or nil."
puts "  def self.lookup(cp : UInt32) : StaticArray(UInt32, 4)?"
puts "    lo = 0"
puts "    hi = TABLE.size - 1"
puts "    while lo <= hi"
puts "      mid = lo + (hi - lo) // 2"
puts "      key = TABLE.unsafe_fetch(mid)[0]"
puts "      if key == cp"
puts "        return TABLE.unsafe_fetch(mid)[1]"
puts "      elsif key < cp"
puts "        lo = mid + 1"
puts "      else"
puts "        hi = mid - 1"
puts "      end"
puts "    end"
puts "    nil"
puts "  end"
puts "end"
