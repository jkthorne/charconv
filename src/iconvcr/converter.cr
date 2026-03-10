class Iconvcr::Converter
  getter from : EncodingInfo
  getter to : EncodingInfo
  @decode_table : Pointer(UInt16)
  @encode_table : Pointer(UInt8)

  def initialize(from_encoding : String, to_encoding : String)
    @from = Registry.lookup(from_encoding) || raise ArgumentError.new("Unknown encoding: #{from_encoding}")
    @to = Registry.lookup(to_encoding) || raise ArgumentError.new("Unknown encoding: #{to_encoding}")
    @state_decode = CodecState.new
    @state_encode = CodecState.new
    @decode_table = Tables::DECODE_TABLES[@from.id.value]
    @encode_table = Tables::ENCODE_TABLES[@to.id.value]
    init_codec_modes
  end

  private def init_codec_modes
    # Decode side
    case @from.id
    when .utf16_be?, .ucs2_be?
      @state_decode.mode = 1_u8 # BE
    when .utf16_le?, .ucs2_le?
      @state_decode.mode = 2_u8 # LE
    when .utf32_be?, .ucs4_be?
      @state_decode.mode = 1_u8
    when .utf32_le?, .ucs4_le?
      @state_decode.mode = 2_u8
    when .ucs2_internal?, .ucs4_internal?
      {% if flag?(:little_endian) %}
        @state_decode.mode = 2_u8 # LE
      {% else %}
        @state_decode.mode = 1_u8 # BE
      {% end %}
    when .ucs2_swapped?, .ucs4_swapped?
      {% if flag?(:little_endian) %}
        @state_decode.mode = 1_u8 # BE (swapped from native LE)
      {% else %}
        @state_decode.mode = 2_u8 # LE (swapped from native BE)
      {% end %}
    when .utf16?, .utf32?, .ucs2?, .ucs4?
      @state_decode.mode = 0_u8 # BOM detection needed
    when .utf7?
      @state_decode.mode = 1_u8 # direct mode
    else
      @state_decode.mode = 1_u8 # default: no BOM detection
    end

    # Encode side
    case @to.id
    when .utf16_be?, .ucs2_be?
      @state_encode.mode = 1_u8
    when .utf16_le?, .ucs2_le?
      @state_encode.mode = 2_u8
    when .utf32_be?, .ucs4_be?
      @state_encode.mode = 1_u8
    when .utf32_le?, .ucs4_le?
      @state_encode.mode = 2_u8
    when .ucs2_internal?, .ucs4_internal?
      {% if flag?(:little_endian) %}
        @state_encode.mode = 2_u8
      {% else %}
        @state_encode.mode = 1_u8
      {% end %}
    when .ucs2_swapped?, .ucs4_swapped?
      {% if flag?(:little_endian) %}
        @state_encode.mode = 1_u8
      {% else %}
        @state_encode.mode = 2_u8
      {% end %}
    when .utf16?, .utf32?, .ucs2?, .ucs4?
      @state_encode.mode = 0_u8 # will emit BOM
    when .utf7?
      @state_encode.mode = 1_u8 # direct mode
    else
      @state_encode.mode = 1_u8
    end
  end

  # Consume BOM from decode source. Returns bytes to skip.
  private def consume_decode_bom(src : Bytes) : Int32
    case @from.id
    when .utf16?, .ucs2?
      return 0 if src.size < 2
      if src.unsafe_fetch(0) == 0xFE_u8 && src.unsafe_fetch(1) == 0xFF_u8
        @state_decode.mode = 1_u8 # BE
        return 2
      elsif src.unsafe_fetch(0) == 0xFF_u8 && src.unsafe_fetch(1) == 0xFE_u8
        @state_decode.mode = 2_u8 # LE
        return 2
      else
        @state_decode.mode = 1_u8 # default BE
        return 0
      end
    when .utf32?, .ucs4?
      return 0 if src.size < 4
      if src.unsafe_fetch(0) == 0x00_u8 && src.unsafe_fetch(1) == 0x00_u8 &&
         src.unsafe_fetch(2) == 0xFE_u8 && src.unsafe_fetch(3) == 0xFF_u8
        @state_decode.mode = 1_u8 # BE
        return 4
      elsif src.unsafe_fetch(0) == 0xFF_u8 && src.unsafe_fetch(1) == 0xFE_u8 &&
            src.unsafe_fetch(2) == 0x00_u8 && src.unsafe_fetch(3) == 0x00_u8
        @state_decode.mode = 2_u8 # LE
        return 4
      else
        @state_decode.mode = 1_u8 # default BE
        return 0
      end
    else
      @state_decode.mode = 1_u8
      return 0
    end
  end

  # Emit BOM to encode output. Returns bytes written.
  private def emit_encode_bom(dst : Bytes) : Int32
    case @to.id
    when .utf16?, .ucs2?
      return 0 if dst.size < 2
      # Emit BE BOM (FE FF) and set mode to BE
      dst.to_unsafe[0] = 0xFE_u8
      dst.to_unsafe[1] = 0xFF_u8
      @state_encode.mode = 1_u8 # BE
      return 2
    when .utf32?, .ucs4?
      return 0 if dst.size < 4
      # Emit BE BOM (00 00 FE FF) and set mode to BE
      dst.to_unsafe[0] = 0x00_u8
      dst.to_unsafe[1] = 0x00_u8
      dst.to_unsafe[2] = 0xFE_u8
      dst.to_unsafe[3] = 0xFF_u8
      @state_encode.mode = 1_u8 # BE
      return 4
    else
      @state_encode.mode = 1_u8
      return 0
    end
  end

  # Scans a run of ASCII bytes using 8-byte word reads.
  @[AlwaysInline]
  private def scan_ascii_run(src : Bytes, from : Int32) : Int32
    pos = from
    remaining = src.size - pos

    while remaining >= 8
      word = (src.to_unsafe + pos).as(Pointer(UInt64)).value
      break if word & 0x8080808080808080_u64 != 0
      pos += 8
      remaining -= 8
    end

    while pos < src.size
      break if src.unsafe_fetch(pos) >= 0x80_u8
      pos += 1
    end

    pos - from
  end

  @[AlwaysInline]
  private def decode_one(src : Bytes, pos : Int32) : DecodeResult
    case @from.id
    when .ascii?      then Decode.ascii(src, pos)
    when .utf8?       then Decode.utf8(src, pos)
    when .iso_8859_1? then Decode.iso_8859_1(src, pos)
    when .utf16_be?   then Codec::UTF16.decode_be(src, pos)
    when .utf16_le?   then Codec::UTF16.decode_le(src, pos)
    when .utf16?
      @state_decode.mode == 2_u8 ? Codec::UTF16.decode_le(src, pos) : Codec::UTF16.decode_be(src, pos)
    when .utf32_be?   then Codec::UTF32.decode_be(src, pos)
    when .utf32_le?   then Codec::UTF32.decode_le(src, pos)
    when .utf32?
      @state_decode.mode == 2_u8 ? Codec::UTF32.decode_le(src, pos) : Codec::UTF32.decode_be(src, pos)
    when .ucs2_be?
      Codec::UTF16.decode_ucs2_be(src, pos)
    when .ucs2_le?
      Codec::UTF16.decode_ucs2_le(src, pos)
    when .ucs2?
      @state_decode.mode == 2_u8 ? Codec::UTF16.decode_ucs2_le(src, pos) : Codec::UTF16.decode_ucs2_be(src, pos)
    when .ucs2_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF16.decode_ucs2_le(src, pos)
      {% else %}
        Codec::UTF16.decode_ucs2_be(src, pos)
      {% end %}
    when .ucs2_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF16.decode_ucs2_be(src, pos)
      {% else %}
        Codec::UTF16.decode_ucs2_le(src, pos)
      {% end %}
    when .ucs4_be?    then Codec::UTF32.decode_be(src, pos)
    when .ucs4_le?    then Codec::UTF32.decode_le(src, pos)
    when .ucs4?
      @state_decode.mode == 2_u8 ? Codec::UTF32.decode_le(src, pos) : Codec::UTF32.decode_be(src, pos)
    when .ucs4_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF32.decode_le(src, pos)
      {% else %}
        Codec::UTF32.decode_be(src, pos)
      {% end %}
    when .ucs4_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF32.decode_be(src, pos)
      {% else %}
        Codec::UTF32.decode_le(src, pos)
      {% end %}
    when .utf7?
      Codec::UTF7.decode(src, pos, pointerof(@state_decode))
    when .c99?  then Codec::C99.decode(src, pos)
    when .java? then Codec::Java.decode(src, pos)
    else Decode.single_byte_table(src, pos, @decode_table)
    end
  end

  @[AlwaysInline]
  private def encode_one(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    case @to.id
    when .ascii?      then Encode.ascii(cp, dst, pos)
    when .utf8?       then Encode.utf8(cp, dst, pos)
    when .iso_8859_1? then Encode.iso_8859_1(cp, dst, pos)
    when .utf16_be?   then Codec::UTF16.encode_be(cp, dst, pos)
    when .utf16_le?   then Codec::UTF16.encode_le(cp, dst, pos)
    when .utf16?
      @state_encode.mode == 2_u8 ? Codec::UTF16.encode_le(cp, dst, pos) : Codec::UTF16.encode_be(cp, dst, pos)
    when .utf32_be?   then Codec::UTF32.encode_be(cp, dst, pos)
    when .utf32_le?   then Codec::UTF32.encode_le(cp, dst, pos)
    when .utf32?
      @state_encode.mode == 2_u8 ? Codec::UTF32.encode_le(cp, dst, pos) : Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs2_be?
      Codec::UTF16.encode_ucs2_be(cp, dst, pos)
    when .ucs2_le?
      Codec::UTF16.encode_ucs2_le(cp, dst, pos)
    when .ucs2?
      @state_encode.mode == 2_u8 ? Codec::UTF16.encode_ucs2_le(cp, dst, pos) : Codec::UTF16.encode_ucs2_be(cp, dst, pos)
    when .ucs2_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF16.encode_ucs2_le(cp, dst, pos)
      {% else %}
        Codec::UTF16.encode_ucs2_be(cp, dst, pos)
      {% end %}
    when .ucs2_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF16.encode_ucs2_be(cp, dst, pos)
      {% else %}
        Codec::UTF16.encode_ucs2_le(cp, dst, pos)
      {% end %}
    when .ucs4_be?    then Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs4_le?    then Codec::UTF32.encode_le(cp, dst, pos)
    when .ucs4?
      @state_encode.mode == 2_u8 ? Codec::UTF32.encode_le(cp, dst, pos) : Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs4_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF32.encode_le(cp, dst, pos)
      {% else %}
        Codec::UTF32.encode_be(cp, dst, pos)
      {% end %}
    when .ucs4_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF32.encode_be(cp, dst, pos)
      {% else %}
        Codec::UTF32.encode_le(cp, dst, pos)
      {% end %}
    when .utf7?
      Codec::UTF7.encode(cp, dst, pos, pointerof(@state_encode))
    when .c99?  then Codec::C99.encode(cp, dst, pos)
    when .java? then Codec::Java.encode(cp, dst, pos)
    else Encode.single_byte_table(cp, dst, pos, @encode_table)
    end
  end

  # Fast path for conversions where both encodings are ASCII supersets.
  private def convert_ascii_fast(src : Bytes, dst : Bytes) : {Int32, Int32}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        src.to_unsafe.copy_to(dst.to_unsafe + dst_pos, copy_len) if copy_len > 0
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        break if copy_len < ascii_len
        next
      end

      dr = decode_one(src, src_pos)
      if dr.status == -1
        return {src_pos, dst_pos}
      elsif dr.status == 0
        return {src_pos, dst_pos}
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1
        return {src_pos, dst_pos}
      elsif er.status == 0
        return {src_pos, dst_pos}
      end

      src_pos += dr.status
      dst_pos += er.status
    end

    {src_pos, dst_pos}
  end

  # General character-at-a-time loop for non-ASCII-superset encodings.
  private def convert_general(src : Bytes, dst : Bytes) : {Int32, Int32}
    src_pos = 0
    dst_pos = 0

    # BOM handling — only fires once (when mode == 0)
    if @state_decode.mode == 0_u8
      src_pos = consume_decode_bom(src)
    end
    if @state_encode.mode == 0_u8
      dst_pos = emit_encode_bom(dst)
    end

    while src_pos < src.size
      dr = decode_one(src, src_pos)
      if dr.status == -1
        return {src_pos, dst_pos}
      elsif dr.status == 0
        return {src_pos, dst_pos}
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1
        return {src_pos, dst_pos}
      elsif er.status == 0
        return {src_pos, dst_pos}
      end

      src_pos += dr.status
      dst_pos += er.status
    end

    {src_pos, dst_pos}
  end

  def convert(src : Bytes, dst : Bytes) : {Int32, Int32}
    if @from.ascii_superset && @to.ascii_superset
      convert_ascii_fast(src, dst)
    else
      convert_general(src, dst)
    end
  end

  # One-shot conversion: allocates output buffer, converts, returns trimmed result.
  def convert(input : Bytes) : Bytes
    max_out = input.size.to_i64 * @to.max_bytes_per_char
    # Cap at a reasonable size to avoid absurd allocations on empty input
    max_out = 16_i64 if max_out < 16
    # For BOM-detecting encodings, add space for BOM in output
    max_out += 4 if @to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?
    dst = Bytes.new(max_out)
    src_consumed, dst_written = convert(input, dst)

    # For UTF-7 encode, flush any remaining base64 state
    if @to.id.utf7? && @state_encode.mode == 2_u8
      flush_written = Codec::UTF7.flush_base64(dst, dst_written, pointerof(@state_encode))
      dst_written += flush_written
    end

    if src_consumed < input.size
      raise Iconvcr::ConversionError.new(
        "Conversion failed at byte #{src_consumed} (#{src_consumed}/#{input.size} bytes consumed)"
      )
    end
    dst[0, dst_written]
  end

  def reset
    @state_decode.reset
    @state_encode.reset
    init_codec_modes
  end
end
