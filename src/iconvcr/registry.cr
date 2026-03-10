module Iconvcr::Registry
  private ASCII_INFO      = EncodingInfo.new(EncodingID::ASCII, true, 1_u8, false)
  private UTF8_INFO       = EncodingInfo.new(EncodingID::UTF8, true, 4_u8, false)
  private ISO_8859_1_INFO = EncodingInfo.new(EncodingID::ISO_8859_1, true, 1_u8, false)

  {% for id in %w[ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
                  ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
                  ISO_8859_15 ISO_8859_16
                  CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
                  KOI8_R KOI8_U KOI8_RU
                  CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
                  CP865 CP866 CP869
                  CP874 TIS_620 ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
                  NEXTSTEP PT154 KOI8_T
                  CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
                  CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1] %}
    private {{ id.upcase.id }}_INFO = EncodingInfo.new(EncodingID::{{ id.id }}, true, 1_u8, false)
  {% end %}

  # Mac encodings, CP864, and VISCII are NOT pure ASCII supersets (byte 0x7F or others differ)
  {% for id in %w[MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
                  MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
                  CP864 VISCII] %}
    private {{ id.upcase.id }}_INFO = EncodingInfo.new(EncodingID::{{ id.id }}, false, 1_u8, false)
  {% end %}

  # EBCDIC encodings and TCVN are NOT ASCII supersets
  {% for id in %w[CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
                  CP423 CP424 CP500 CP905 CP1026 TCVN] %}
    private {{ id.upcase.id }}_INFO = EncodingInfo.new(EncodingID::{{ id.id }}, false, 1_u8, false)
  {% end %}

  # Phase 3: Unicode family encodings (none are ASCII supersets)
  private UTF16_BE_INFO  = EncodingInfo.new(EncodingID::UTF16_BE, false, 4_u8, false)
  private UTF16_LE_INFO  = EncodingInfo.new(EncodingID::UTF16_LE, false, 4_u8, false)
  private UTF16_INFO     = EncodingInfo.new(EncodingID::UTF16, false, 4_u8, true)
  private UTF32_BE_INFO  = EncodingInfo.new(EncodingID::UTF32_BE, false, 4_u8, false)
  private UTF32_LE_INFO  = EncodingInfo.new(EncodingID::UTF32_LE, false, 4_u8, false)
  private UTF32_INFO     = EncodingInfo.new(EncodingID::UTF32, false, 4_u8, true)
  private UCS2_INFO      = EncodingInfo.new(EncodingID::UCS2, false, 2_u8, true)
  private UCS2_BE_INFO   = EncodingInfo.new(EncodingID::UCS2_BE, false, 2_u8, false)
  private UCS2_LE_INFO   = EncodingInfo.new(EncodingID::UCS2_LE, false, 2_u8, false)
  private UCS2_INTERNAL_INFO = EncodingInfo.new(EncodingID::UCS2_INTERNAL, false, 2_u8, false)
  private UCS2_SWAPPED_INFO  = EncodingInfo.new(EncodingID::UCS2_SWAPPED, false, 2_u8, false)
  private UCS4_INFO      = EncodingInfo.new(EncodingID::UCS4, false, 4_u8, true)
  private UCS4_BE_INFO   = EncodingInfo.new(EncodingID::UCS4_BE, false, 4_u8, false)
  private UCS4_LE_INFO   = EncodingInfo.new(EncodingID::UCS4_LE, false, 4_u8, false)
  private UCS4_INTERNAL_INFO = EncodingInfo.new(EncodingID::UCS4_INTERNAL, false, 4_u8, false)
  private UCS4_SWAPPED_INFO  = EncodingInfo.new(EncodingID::UCS4_SWAPPED, false, 4_u8, false)
  private UTF7_INFO      = EncodingInfo.new(EncodingID::UTF7, false, 8_u8, true)
  private C99_INFO       = EncodingInfo.new(EncodingID::C99, false, 10_u8, false)
  private JAVA_INFO      = EncodingInfo.new(EncodingID::JAVA, false, 12_u8, false)

  ENCODINGS = {
    # ASCII
    "ASCII"       => ASCII_INFO,
    "USASCII"     => ASCII_INFO,
    "ANSIX341968" => ASCII_INFO,
    "ISO646US"    => ASCII_INFO,

    # UTF-8
    "UTF8" => UTF8_INFO,

    # ISO-8859-1
    "ISO88591"     => ISO_8859_1_INFO,
    "LATIN1"       => ISO_8859_1_INFO,
    "ISO885911987"  => ISO_8859_1_INFO,
    "CP819"        => ISO_8859_1_INFO,
    "IBM819"       => ISO_8859_1_INFO,

    # ISO-8859-2
    "ISO88592"     => ISO_8859_2_INFO,
    "LATIN2"       => ISO_8859_2_INFO,
    "ISO885921987" => ISO_8859_2_INFO,
    "ISOIR101"     => ISO_8859_2_INFO,

    # ISO-8859-3
    "ISO88593"     => ISO_8859_3_INFO,
    "LATIN3"       => ISO_8859_3_INFO,
    "ISO885931988" => ISO_8859_3_INFO,
    "ISOIR109"     => ISO_8859_3_INFO,

    # ISO-8859-4
    "ISO88594"     => ISO_8859_4_INFO,
    "LATIN4"       => ISO_8859_4_INFO,
    "ISO885941988" => ISO_8859_4_INFO,
    "ISOIR110"     => ISO_8859_4_INFO,

    # ISO-8859-5
    "ISO88595"     => ISO_8859_5_INFO,
    "CYRILLIC"     => ISO_8859_5_INFO,
    "ISO885951988" => ISO_8859_5_INFO,
    "ISOIR144"     => ISO_8859_5_INFO,

    # ISO-8859-6
    "ISO88596"     => ISO_8859_6_INFO,
    "ARABIC"       => ISO_8859_6_INFO,
    "ISO885961987" => ISO_8859_6_INFO,
    "ISOIR127"     => ISO_8859_6_INFO,
    "ASMO708"      => ISO_8859_6_INFO,
    "ECMA114"      => ISO_8859_6_INFO,

    # ISO-8859-7
    "ISO88597"     => ISO_8859_7_INFO,
    "GREEK"        => ISO_8859_7_INFO,
    "GREEK8"       => ISO_8859_7_INFO,
    "ISO885972003" => ISO_8859_7_INFO,
    "ISO885971987" => ISO_8859_7_INFO,
    "ISOIR126"     => ISO_8859_7_INFO,
    "ECMA118"      => ISO_8859_7_INFO,
    "ELOT928"      => ISO_8859_7_INFO,

    # ISO-8859-8
    "ISO88598"     => ISO_8859_8_INFO,
    "HEBREW"       => ISO_8859_8_INFO,
    "ISO885981988" => ISO_8859_8_INFO,
    "ISOIR138"     => ISO_8859_8_INFO,

    # ISO-8859-9
    "ISO88599"     => ISO_8859_9_INFO,
    "LATIN5"       => ISO_8859_9_INFO,
    "ISO885991989" => ISO_8859_9_INFO,
    "ISOIR148"     => ISO_8859_9_INFO,

    # ISO-8859-10
    "ISO885910"     => ISO_8859_10_INFO,
    "LATIN6"        => ISO_8859_10_INFO,
    "ISO8859101992" => ISO_8859_10_INFO,
    "ISOIR157"      => ISO_8859_10_INFO,

    # ISO-8859-11
    "ISO885911" => ISO_8859_11_INFO,

    # ISO-8859-13
    "ISO885913" => ISO_8859_13_INFO,
    "LATIN7"    => ISO_8859_13_INFO,
    "ISOIR179"  => ISO_8859_13_INFO,

    # ISO-8859-14
    "ISO885914"     => ISO_8859_14_INFO,
    "LATIN8"        => ISO_8859_14_INFO,
    "ISO8859141998" => ISO_8859_14_INFO,
    "ISOIR199"      => ISO_8859_14_INFO,
    "ISOCELTIC"     => ISO_8859_14_INFO,

    # ISO-8859-15
    "ISO885915"     => ISO_8859_15_INFO,
    "LATIN9"        => ISO_8859_15_INFO,
    "ISO8859151998" => ISO_8859_15_INFO,
    "ISOIR203"      => ISO_8859_15_INFO,

    # ISO-8859-16
    "ISO885916"     => ISO_8859_16_INFO,
    "LATIN10"       => ISO_8859_16_INFO,
    "ISO8859162001" => ISO_8859_16_INFO,
    "ISOIR226"      => ISO_8859_16_INFO,

    # Windows code pages
    "CP1250"       => CP1250_INFO,
    "WINDOWS1250"  => CP1250_INFO,
    "MSEE"         => CP1250_INFO,

    "CP1251"       => CP1251_INFO,
    "WINDOWS1251"  => CP1251_INFO,
    "MSCYRL"       => CP1251_INFO,

    "CP1252"       => CP1252_INFO,
    "WINDOWS1252"  => CP1252_INFO,
    "MSANSI"       => CP1252_INFO,

    "CP1253"       => CP1253_INFO,
    "WINDOWS1253"  => CP1253_INFO,
    "MSGREEK"      => CP1253_INFO,

    "CP1254"       => CP1254_INFO,
    "WINDOWS1254"  => CP1254_INFO,
    "MSTURK"       => CP1254_INFO,

    "CP1255"       => CP1255_INFO,
    "WINDOWS1255"  => CP1255_INFO,
    "MSHEBR"       => CP1255_INFO,

    "CP1256"       => CP1256_INFO,
    "WINDOWS1256"  => CP1256_INFO,
    "MSARAB"       => CP1256_INFO,

    "CP1257"       => CP1257_INFO,
    "WINDOWS1257"  => CP1257_INFO,
    "WINBALTRIM"   => CP1257_INFO,

    "CP1258"       => CP1258_INFO,
    "WINDOWS1258"  => CP1258_INFO,

    # KOI8
    "KOI8R"  => KOI8_R_INFO,
    "KOI8U"  => KOI8_U_INFO,
    "KOI8RU" => KOI8_RU_INFO,

    # Mac encodings
    "MACROMAN"          => MAC_ROMAN_INFO,
    "MACINTOSH"         => MAC_ROMAN_INFO,
    "MAC"               => MAC_ROMAN_INFO,
    "MACCENTRALEUROPE"  => MAC_CENTRAL_EUROPE_INFO,
    "MACICELAND"        => MAC_ICELAND_INFO,
    "MACCROATIAN"       => MAC_CROATIAN_INFO,
    "MACROMANIA"        => MAC_ROMANIA_INFO,
    "MACCYRILLIC"       => MAC_CYRILLIC_INFO,
    "MACUKRAINE"        => MAC_UKRAINE_INFO,
    "MACGREEK"          => MAC_GREEK_INFO,
    "MACTURKISH"        => MAC_TURKISH_INFO,
    "MACHEBREW"         => MAC_HEBREW_INFO,
    "MACARABIC"         => MAC_ARABIC_INFO,
    "MACTHAI"           => MAC_THAI_INFO,

    # DOS code pages
    "CP437"  => CP437_INFO,
    "IBM437" => CP437_INFO,
    "437"    => CP437_INFO,

    "CP737" => CP737_INFO,

    "CP775"  => CP775_INFO,
    "IBM775" => CP775_INFO,

    "CP850"  => CP850_INFO,
    "IBM850" => CP850_INFO,
    "850"    => CP850_INFO,

    "CP852"  => CP852_INFO,
    "IBM852" => CP852_INFO,
    "852"    => CP852_INFO,

    "CP855"  => CP855_INFO,
    "IBM855" => CP855_INFO,
    "855"    => CP855_INFO,

    "CP857"  => CP857_INFO,
    "IBM857" => CP857_INFO,
    "857"    => CP857_INFO,

    "CP858" => CP858_INFO,

    "CP860"  => CP860_INFO,
    "IBM860" => CP860_INFO,
    "860"    => CP860_INFO,

    "CP861"  => CP861_INFO,
    "IBM861" => CP861_INFO,
    "861"    => CP861_INFO,
    "CPIS"   => CP861_INFO,

    "CP862"  => CP862_INFO,
    "IBM862" => CP862_INFO,
    "862"    => CP862_INFO,

    "CP863"  => CP863_INFO,
    "IBM863" => CP863_INFO,
    "863"    => CP863_INFO,

    "CP864"  => CP864_INFO,
    "IBM864" => CP864_INFO,

    "CP865"  => CP865_INFO,
    "IBM865" => CP865_INFO,
    "865"    => CP865_INFO,

    "CP866"  => CP866_INFO,
    "IBM866" => CP866_INFO,
    "866"    => CP866_INFO,

    "CP869"  => CP869_INFO,
    "IBM869" => CP869_INFO,
    "869"    => CP869_INFO,
    "CPGR"   => CP869_INFO,

    # Other single-byte
    "CP874"      => CP874_INFO,
    "WINDOWS874" => CP874_INFO,

    "TIS620"       => TIS_620_INFO,
    "TIS6200"      => TIS_620_INFO,
    "TIS62025291"  => TIS_620_INFO,
    "TIS62025330"  => TIS_620_INFO,
    "TIS62025331"  => TIS_620_INFO,
    "ISOIR166"     => TIS_620_INFO,

    "VISCII"    => VISCII_INFO,
    "VISCII111" => VISCII_INFO,

    "ARMSCII8" => ARMSCII_8_INFO,

    "GEORGIANACADEMY" => GEORGIAN_ACADEMY_INFO,
    "GEORGIANPS"      => GEORGIAN_PS_INFO,

    "HPROMAN8" => HP_ROMAN8_INFO,
    "ROMAN8"   => HP_ROMAN8_INFO,
    "R8"       => HP_ROMAN8_INFO,

    "NEXTSTEP" => NEXTSTEP_INFO,

    "PT154"    => PT154_INFO,
    "CP154"    => PT154_INFO,
    "PTCP154"  => PT154_INFO,

    "KOI8T" => KOI8_T_INFO,

    # Phase 3: Unicode family encodings
    "UTF16BE" => UTF16_BE_INFO,
    "UTF16LE" => UTF16_LE_INFO,
    "UTF16"   => UTF16_INFO,

    "UTF32BE" => UTF32_BE_INFO,
    "UTF32LE" => UTF32_LE_INFO,
    "UTF32"   => UTF32_INFO,

    "UCS2"          => UCS2_INFO,
    "ISO10646UCS2"  => UCS2_INFO,
    "CSUNICODE"     => UCS2_INFO,
    "UCS2BE"        => UCS2_BE_INFO,
    "UNICODE11"     => UCS2_BE_INFO,
    "UNICODEBIG"    => UCS2_BE_INFO,
    "CSUNICODE11"   => UCS2_BE_INFO,
    "UCS2LE"        => UCS2_LE_INFO,
    "UNICODELITTLE"  => UCS2_LE_INFO,
    "UCS2INTERNAL"  => UCS2_INTERNAL_INFO,
    "UCS2SWAPPED"   => UCS2_SWAPPED_INFO,

    "UCS4"          => UCS4_INFO,
    "ISO10646UCS4"  => UCS4_INFO,
    "CSUCS4"        => UCS4_INFO,
    "UCS4BE"        => UCS4_BE_INFO,
    "UCS4LE"        => UCS4_LE_INFO,
    "UCS4INTERNAL"  => UCS4_INTERNAL_INFO,
    "UCS4SWAPPED"   => UCS4_SWAPPED_INFO,

    "UTF7"            => UTF7_INFO,
    "UNICODE11UTF7"   => UTF7_INFO,
    "CSUNICODE11UTF7" => UTF7_INFO,

    "C99"  => C99_INFO,
    "JAVA" => JAVA_INFO,

    # Phase 5: EBCDIC encodings
    "CP037"       => CP037_INFO,
    "IBM037"      => CP037_INFO,
    "EBCDICCP037" => CP037_INFO,

    "CP273"  => CP273_INFO,
    "IBM273" => CP273_INFO,

    "CP277"  => CP277_INFO,
    "IBM277" => CP277_INFO,

    "CP278"  => CP278_INFO,
    "IBM278" => CP278_INFO,

    "CP280"  => CP280_INFO,
    "IBM280" => CP280_INFO,

    "CP284"  => CP284_INFO,
    "IBM284" => CP284_INFO,

    "CP285"  => CP285_INFO,
    "IBM285" => CP285_INFO,

    "CP297"  => CP297_INFO,
    "IBM297" => CP297_INFO,

    "CP423"  => CP423_INFO,
    "IBM423" => CP423_INFO,

    "CP424"  => CP424_INFO,
    "IBM424" => CP424_INFO,

    "CP500"       => CP500_INFO,
    "IBM500"      => CP500_INFO,
    "EBCDICCP500" => CP500_INFO,

    "CP905"  => CP905_INFO,
    "IBM905" => CP905_INFO,

    "CP1026"  => CP1026_INFO,
    "IBM1026" => CP1026_INFO,

    # Phase 5: ASCII-superset single-byte
    "CP856"  => CP856_INFO,
    "IBM856" => CP856_INFO,

    "CP922"  => CP922_INFO,
    "IBM922" => CP922_INFO,

    "CP853"  => CP853_INFO,

    "CP1046" => CP1046_INFO,

    "CP1124" => CP1124_INFO,

    "CP1125" => CP1125_INFO,

    "CP1129" => CP1129_INFO,

    "CP1131" => CP1131_INFO,

    "CP1133" => CP1133_INFO,

    "CP1161" => CP1161_INFO,

    "CP1162" => CP1162_INFO,

    "CP1163" => CP1163_INFO,

    "ATARIST" => ATARIST_INFO,

    "KZ1048"       => KZ_1048_INFO,
    "STRK10482002" => KZ_1048_INFO,
    "RK1048"       => KZ_1048_INFO,

    "MULELAO1" => MULELAO_1_INFO,

    "RISCOSLATIN1" => RISCOS_LATIN1_INFO,

    # Phase 5: Non-ASCII non-EBCDIC
    "TCVN"      => TCVN_INFO,
    "TCVN5712"  => TCVN_INFO,
    "TCVN57121" => TCVN_INFO,
  }

  CANONICAL_NAMES = [
    "ASCII", "UTF-8", "ISO-8859-1",
    "ISO-8859-2", "ISO-8859-3", "ISO-8859-4", "ISO-8859-5", "ISO-8859-6",
    "ISO-8859-7", "ISO-8859-8", "ISO-8859-9", "ISO-8859-10", "ISO-8859-11",
    "ISO-8859-13", "ISO-8859-14", "ISO-8859-15", "ISO-8859-16",
    "CP1250", "CP1251", "CP1252", "CP1253", "CP1254", "CP1255", "CP1256", "CP1257", "CP1258",
    "KOI8-R", "KOI8-U", "KOI8-RU",
    "MacRoman", "MacCentralEurope", "MacIceland", "MacCroatian", "MacRomania",
    "MacCyrillic", "MacUkraine", "MacGreek", "MacTurkish", "MacHebrew", "MacArabic", "MacThai",
    "CP437", "CP737", "CP775", "CP850", "CP852", "CP855", "CP857", "CP858",
    "CP860", "CP861", "CP862", "CP863", "CP864", "CP865", "CP866", "CP869",
    "CP874", "TIS-620", "VISCII", "ARMSCII-8",
    "Georgian-Academy", "Georgian-PS", "HP-Roman8", "NEXTSTEP", "PT154", "KOI8-T",
    # Phase 3: Unicode family
    "UTF-16BE", "UTF-16LE", "UTF-16",
    "UTF-32BE", "UTF-32LE", "UTF-32",
    "UCS-2", "UCS-2BE", "UCS-2LE", "UCS-2-INTERNAL", "UCS-2-SWAPPED",
    "UCS-4", "UCS-4BE", "UCS-4LE", "UCS-4-INTERNAL", "UCS-4-SWAPPED",
    "UTF-7", "C99", "JAVA",
    # Phase 5: Remaining single-byte
    "CP037", "CP273", "CP277", "CP278", "CP280", "CP284", "CP285", "CP297",
    "CP423", "CP424", "CP500", "CP905", "CP1026",
    "CP856", "CP922", "CP853", "CP1046", "CP1124", "CP1125", "CP1129", "CP1131",
    "CP1133", "CP1161", "CP1162", "CP1163", "ATARIST", "KZ-1048", "MULELAO-1",
    "RISCOS-LATIN1", "TCVN",
  ]

  def self.normalize(name : String) : String
    String.build(name.size) do |io|
      name.each_char do |c|
        if c.ascii_alphanumeric?
          io << c.upcase
        end
      end
    end
  end

  def self.lookup(name : String) : EncodingInfo?
    # Strip //IGNORE and //TRANSLIT suffixes
    clean = name
    if idx = clean.index("//")
      clean = clean[0...idx]
    end
    normalized = normalize(clean)
    ENCODINGS[normalized]?
  end

  def self.canonical_names : Array(String)
    CANONICAL_NAMES.dup
  end
end
