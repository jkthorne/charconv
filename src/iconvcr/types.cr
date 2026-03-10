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
