module CharConv::Tables
  # Indexed by EncodingID.value. Null for ASCII/UTF8/ISO_8859_1 (dedicated codecs).
  DECODE_TABLES = begin
    count = EncodingID.values.size
    arr = Array(Pointer(UInt16)).new(count, Pointer(UInt16).null)
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
      arr[EncodingID::{{ enc.id }}.value] = SingleByte::{{ enc.id }}_DECODE.to_unsafe
    {% end %}
    arr
  end

  ENCODE_TABLES = begin
    count = EncodingID.values.size
    arr = Array(Pointer(UInt8)).new(count, Pointer(UInt8).null)
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
      arr[EncodingID::{{ enc.id }}.value] = build_encode_table(SingleByte::{{ enc.id }}_DECODE, SingleByte::{{ enc.id }}_ENCODE_PAIRS)
    {% end %}
    arr
  end

  private def self.build_encode_table(decode : StaticArray(UInt16, 256), pairs : Array({UInt16, UInt8})) : Pointer(UInt8)
    table = Pointer(UInt8).malloc(65536, 0_u8)
    # Invert decode table: for each byte, set encode[codepoint] = byte
    (0..255).each do |b|
      cp = decode[b]
      table[cp] = b.to_u8 if cp != 0xFFFF_u16
    end
    # Apply system iconv encode preferences (overrides where different)
    pairs.each { |cp, byte| table[cp] = byte }
    table
  end
end
