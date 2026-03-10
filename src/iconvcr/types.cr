module Iconvcr
  # Stack-allocated result from decoding one character.
  # `status` > 0: number of bytes consumed; `codepoint` is the decoded value.
  # `status` == 0: incomplete sequence (need more input).
  # `status` == -1: illegal sequence.
  struct DecodeResult
    getter codepoint : UInt32
    getter status : Int32

    def initialize(@codepoint : UInt32, @status : Int32)
    end

    ILSEQ  = new(0_u32, -1)
    TOOFEW = new(0_u32, 0)

    @[AlwaysInline]
    def ok? : Bool
      @status > 0
    end
  end

  # Stack-allocated result from encoding one codepoint.
  # `status` > 0: number of bytes written.
  # `status` == 0: output buffer too small.
  # `status` == -1: codepoint not representable in target encoding.
  struct EncodeResult
    getter status : Int32

    def initialize(@status : Int32)
    end

    ILUNI    = new(-1)
    TOOSMALL = new(0)

    @[AlwaysInline]
    def ok? : Bool
      @status > 0
    end
  end

  enum EncodingID : UInt16
    ASCII
    UTF8
    ISO_8859_1
    ISO_8859_2
    ISO_8859_3
    ISO_8859_4
    ISO_8859_5
    ISO_8859_6
    ISO_8859_7
    ISO_8859_8
    ISO_8859_9
    ISO_8859_10
    ISO_8859_11
    ISO_8859_13
    ISO_8859_14
    ISO_8859_15
    ISO_8859_16
    CP1250
    CP1251
    CP1252
    CP1253
    CP1254
    CP1255
    CP1256
    CP1257
    CP1258
    KOI8_R
    KOI8_U
    KOI8_RU
    MAC_ROMAN
    MAC_CENTRAL_EUROPE
    MAC_ICELAND
    MAC_CROATIAN
    MAC_ROMANIA
    MAC_CYRILLIC
    MAC_UKRAINE
    MAC_GREEK
    MAC_TURKISH
    MAC_HEBREW
    MAC_ARABIC
    MAC_THAI
    CP437
    CP737
    CP775
    CP850
    CP852
    CP855
    CP857
    CP858
    CP860
    CP861
    CP862
    CP863
    CP864
    CP865
    CP866
    CP869
    CP874
    TIS_620
    VISCII
    ARMSCII_8
    GEORGIAN_ACADEMY
    GEORGIAN_PS
    HP_ROMAN8
    NEXTSTEP
    PT154
    KOI8_T
    # Phase 3: Unicode family encodings
    UTF16_BE
    UTF16_LE
    UTF16
    UTF32_BE
    UTF32_LE
    UTF32
    UCS2
    UCS2_BE
    UCS2_LE
    UCS2_INTERNAL
    UCS2_SWAPPED
    UCS4
    UCS4_BE
    UCS4_LE
    UCS4_INTERNAL
    UCS4_SWAPPED
    UTF7
    C99
    JAVA
    # Phase 5: Remaining single-byte encodings
    # EBCDIC (NOT ASCII supersets)
    CP037
    CP273
    CP277
    CP278
    CP280
    CP284
    CP285
    CP297
    CP423
    CP424
    CP500
    CP905
    CP1026
    # ASCII-superset single-byte
    CP856
    CP922
    CP853
    CP1046
    CP1124
    CP1125
    CP1129
    CP1131
    CP1133
    CP1161
    CP1162
    CP1163
    ATARIST
    KZ_1048
    MULELAO_1
    RISCOS_LATIN1
    # Non-ASCII non-EBCDIC
    TCVN
    # Phase 4: CJK encodings
    # Japanese
    EUC_JP
    SHIFT_JIS
    CP932
    ISO2022_JP
    ISO2022_JP1
    ISO2022_JP2
    # Chinese (Simplified)
    GB2312
    GBK
    GB18030
    EUC_CN
    HZ
    ISO2022_CN
    ISO2022_CN_EXT
    # Chinese (Traditional)
    BIG5
    CP950
    BIG5_HKSCS
    EUC_TW
    # Korean
    EUC_KR
    CP949
    ISO2022_KR
    JOHAB
  end

  struct EncodingInfo
    getter id : EncodingID
    getter ascii_superset : Bool
    getter max_bytes_per_char : UInt8
    getter stateful : Bool

    def initialize(@id : EncodingID, @ascii_superset : Bool, @max_bytes_per_char : UInt8, @stateful : Bool)
    end
  end

  # Per-codec mutable state. Unused in Phase 1 (stateless encodings only)
  # but establishes the struct layout for future stateful codecs.
  @[Flags]
  enum ConversionFlags : UInt8
    Ignore   = 1 # //IGNORE — skip bad input bytes & unencodable chars
    Translit = 2 # //TRANSLIT — try fallback mappings before giving up
  end

  struct CodecState
    property mode : UInt8
    property flags : UInt8
    property buffer : UInt32
    property count : UInt8

    def initialize
      @mode = 0_u8
      @flags = 0_u8
      @buffer = 0_u32
      @count = 0_u8
    end

    def reset
      @mode = 0_u8
      @flags = 0_u8
      @buffer = 0_u32
      @count = 0_u8
    end
  end
end
