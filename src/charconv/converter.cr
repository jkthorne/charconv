class CharConv::Converter
  getter from : EncodingInfo
  getter to : EncodingInfo
  getter flags : ConversionFlags
  @decode_table : Pointer(UInt16)
  @encode_table : Pointer(UInt8)

  def initialize(from_encoding : String, to_encoding : String)
    @from = Registry.lookup(from_encoding) || raise ArgumentError.new("Unknown encoding: #{from_encoding}")
    @to = Registry.lookup(to_encoding) || raise ArgumentError.new("Unknown encoding: #{to_encoding}")
    @flags = Registry.parse_flags(to_encoding)
    @state_decode = CodecState.new
    @state_encode = CodecState.new
    @decode_table = Tables::DECODE_TABLES[@from.id.value]
    @encode_table = Tables::ENCODE_TABLES[@to.id.value]
    init_codec_modes
  end

  private def init_codec_modes
    @state_decode.mode, @state_decode.flags = codec_mode_for(@from.id)
    @state_encode.mode, @state_encode.flags = codec_mode_for(@to.id)
  end

  private def codec_mode_for(id : EncodingID) : {UInt8, UInt8}
    case id
    when .utf16_be?, .ucs2_be?  then {1_u8, 0_u8}
    when .utf16_le?, .ucs2_le?  then {2_u8, 0_u8}
    when .utf32_be?, .ucs4_be?  then {1_u8, 0_u8}
    when .utf32_le?, .ucs4_le?  then {2_u8, 0_u8}
    when .ucs2_internal?, .ucs4_internal?
      {% if flag?(:little_endian) %}
        {2_u8, 0_u8}
      {% else %}
        {1_u8, 0_u8}
      {% end %}
    when .ucs2_swapped?, .ucs4_swapped?
      {% if flag?(:little_endian) %}
        {1_u8, 0_u8} # BE (swapped from native LE)
      {% else %}
        {2_u8, 0_u8} # LE (swapped from native BE)
      {% end %}
    when .utf16?, .utf32?, .ucs2?, .ucs4?
      {0_u8, 0_u8} # BOM detection / will emit BOM
    when .utf7?
      {1_u8, 0_u8} # direct mode
    when .hz?, .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?,
         .iso2022_cn?, .iso2022_cn_ext?, .iso2022_kr?
      {0_u8, 0_u8} # ASCII mode
    else
      {1_u8, 0_u8} # default
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
    # CJK stateless
    when .euc_jp?      then Codec::CJK.decode_euc_jp(src, pos)
    when .shift_jis?   then Codec::CJK.decode_shift_jis(src, pos)
    when .cp932?       then Codec::CJK.decode_cp932(src, pos)
    when .gbk?         then Codec::CJK.decode_gbk(src, pos)
    when .euc_cn?, .gb2312? then Codec::CJK.decode_euc_cn(src, pos)
    when .big5?        then Codec::CJK.decode_big5(src, pos)
    when .cp950?       then Codec::CJK.decode_cp950(src, pos)
    when .big5_hkscs?  then Codec::CJK.decode_big5_hkscs(src, pos)
    when .euc_kr?      then Codec::CJK.decode_euc_kr(src, pos)
    when .cp949?       then Codec::CJK.decode_cp949(src, pos)
    when .johab?       then Codec::CJK.decode_johab(src, pos)
    when .euc_tw?      then Codec::CJK.decode_euc_tw(src, pos)
    when .gb18030?     then Codec::GB18030.decode(src, pos)
    # CJK stateful
    when .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?
      Codec::ISO2022JP.decode(src, pos, pointerof(@state_decode))
    when .iso2022_cn?, .iso2022_cn_ext?
      Codec::ISO2022CN.decode(src, pos, pointerof(@state_decode))
    when .iso2022_kr?
      Codec::ISO2022KR.decode(src, pos, pointerof(@state_decode))
    when .hz?
      Codec::HZ.decode(src, pos, pointerof(@state_decode))
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
    # CJK stateless
    when .euc_jp?      then Codec::CJK.encode_euc_jp(cp, dst, pos)
    when .shift_jis?   then Codec::CJK.encode_shift_jis(cp, dst, pos)
    when .cp932?       then Codec::CJK.encode_cp932(cp, dst, pos)
    when .gbk?         then Codec::CJK.encode_gbk(cp, dst, pos)
    when .euc_cn?, .gb2312? then Codec::CJK.encode_euc_cn(cp, dst, pos)
    when .big5?        then Codec::CJK.encode_big5(cp, dst, pos)
    when .cp950?       then Codec::CJK.encode_cp950(cp, dst, pos)
    when .big5_hkscs?  then Codec::CJK.encode_big5_hkscs(cp, dst, pos)
    when .euc_kr?      then Codec::CJK.encode_euc_kr(cp, dst, pos)
    when .cp949?       then Codec::CJK.encode_cp949(cp, dst, pos)
    when .johab?       then Codec::CJK.encode_johab(cp, dst, pos)
    when .euc_tw?      then Codec::CJK.encode_euc_tw(cp, dst, pos)
    when .gb18030?     then Codec::GB18030.encode(cp, dst, pos)
    # CJK stateful
    when .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?
      Codec::ISO2022JP.encode(cp, dst, pos, pointerof(@state_encode))
    when .iso2022_cn?, .iso2022_cn_ext?
      Codec::ISO2022CN.encode(cp, dst, pos, pointerof(@state_encode))
    when .iso2022_kr?
      Codec::ISO2022KR.encode(cp, dst, pos, pointerof(@state_encode))
    when .hz?
      Codec::HZ.encode(cp, dst, pos, pointerof(@state_encode))
    else Encode.single_byte_table(cp, dst, pos, @encode_table)
    end
  end

  # Try to transliterate a codepoint that can't be encoded directly.
  # Returns number of bytes written to dst, or 0 on failure.
  private def transliterate(cp : UInt32, dst : Bytes, dst_pos : Int32) : Int32
    replacement = Transliteration.lookup(cp)
    return 0 unless replacement
    total = 0
    replacement.each do |rcp|
      break if rcp == 0
      er = encode_one(rcp, dst, dst_pos + total)
      return 0 if er.status <= 0 # any failure → whole transliteration fails
      total += er.status
    end
    total
  end

  # Handle a decode error. Returns src bytes to skip (for IGNORE), or nil to stop.
  private def handle_decode_error(status : Int32) : Int32?
    if status == -1 # ILSEQ
      return 1 if @flags.ignore?
    end
    nil # ILSEQ without IGNORE, or TOOFEW — stop
  end

  # Encode a codepoint with translit/ignore fallback.
  # Returns {src_advance, dst_advance}, or nil to stop.
  private def handle_encode(dr : DecodeResult, dst : Bytes, dst_pos : Int32) : {Int32, Int32}?
    er = encode_one(dr.codepoint, dst, dst_pos)
    if er.status == -1 # ILUNI
      if @flags.translit?
        t = transliterate(dr.codepoint, dst, dst_pos)
        return {dr.status, t} if t > 0
      end
      return {dr.status, 0} if @flags.ignore?
      nil
    elsif er.status == 0 # TOOSMALL
      nil
    else
      {dr.status, er.status}
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
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        break if copy_len < ascii_len
        next
      end

      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        return {src_pos, dst_pos}
      end

      result = handle_encode(dr, dst, dst_pos)
      unless result
        return {src_pos, dst_pos}
      end
      src_pos += result[0]
      dst_pos += result[1]
    end

    {src_pos, dst_pos}
  end

  # Status-returning fast path for iconv compatibility.
  private def convert_ascii_fast_status(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        status = dr.status == 0 ? ConvertStatus::EINVAL : ConvertStatus::EILSEQ
        return {src_pos, dst_pos, status}
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1 # ILUNI
        if @flags.translit?
          t = transliterate(dr.codepoint, dst, dst_pos)
          if t > 0
            src_pos += dr.status
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += dr.status
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      elsif er.status == 0 # TOOSMALL
        return {src_pos, dst_pos, ConvertStatus::E2BIG}
      else
        src_pos += dr.status
        dst_pos += er.status
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # General character-at-a-time loop for non-ASCII-superset encodings.
  private def convert_general(src : Bytes, dst : Bytes) : {Int32, Int32}
    src_pos = 0
    dst_pos = 0

    # BOM handling — only for UTF-16/32 family (mode 0 = BOM detection needed)
    if @state_decode.mode == 0_u8 && (@from.id.utf16? || @from.id.utf32? || @from.id.ucs2? || @from.id.ucs4?)
      src_pos = consume_decode_bom(src)
    end
    if @state_encode.mode == 0_u8 && (@to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?)
      dst_pos = emit_encode_bom(dst)
    end

    while src_pos < src.size
      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        return {src_pos, dst_pos}
      end

      # Stateful codecs return codepoint 0 with status > 0 for escape sequences
      # (mode switches that consume bytes but produce no character).
      # Only skip for stateful encodings — stateless codecs decoding to U+0000 is a real NUL.
      if dr.codepoint == 0 && dr.status > 0 && @from.stateful
        src_pos += dr.status
        next
      end

      result = handle_encode(dr, dst, dst_pos)
      unless result
        return {src_pos, dst_pos}
      end
      src_pos += result[0]
      dst_pos += result[1]
    end

    {src_pos, dst_pos}
  end

  # Status-returning general loop for iconv compatibility.
  private def convert_general_status(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    if @state_decode.mode == 0_u8 && (@from.id.utf16? || @from.id.utf32? || @from.id.ucs2? || @from.id.ucs4?)
      src_pos = consume_decode_bom(src)
    end
    if @state_encode.mode == 0_u8 && (@to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?)
      dst_pos = emit_encode_bom(dst)
    end

    while src_pos < src.size
      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        status = dr.status == 0 ? ConvertStatus::EINVAL : ConvertStatus::EILSEQ
        return {src_pos, dst_pos, status}
      end

      if dr.codepoint == 0 && dr.status > 0 && @from.stateful
        src_pos += dr.status
        next
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1 # ILUNI
        if @flags.translit?
          t = transliterate(dr.codepoint, dst, dst_pos)
          if t > 0
            src_pos += dr.status
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += dr.status
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      elsif er.status == 0 # TOOSMALL
        return {src_pos, dst_pos, ConvertStatus::E2BIG}
      else
        src_pos += dr.status
        dst_pos += er.status
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  def convert(src : Bytes, dst : Bytes) : {Int32, Int32}
    if @from.ascii_superset && @to.ascii_superset
      convert_ascii_fast(src, dst)
    else
      convert_general(src, dst)
    end
  end

  # Like convert but returns a status code indicating why conversion stopped.
  # Used by the stdlib iconv bridge to set errno correctly.
  def convert_with_status(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    if @from.ascii_superset && @to.ascii_superset
      convert_ascii_fast_status(src, dst)
    else
      convert_general_status(src, dst)
    end
  end

  # One-shot conversion: allocates output buffer, converts, returns trimmed result.
  def convert(input : Bytes) : Bytes
    max_out = input.size.to_i64 * @to.max_bytes_per_char
    # Cap at a reasonable size to avoid absurd allocations on empty input
    max_out = 16_i64 if max_out < 16
    # Transliteration can expand 1 char → up to 4 chars
    max_out = max_out * 4 if @flags.translit?
    # For BOM-detecting encodings, add space for BOM in output
    max_out += 4 if @to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?
    # For stateful encodings, add space for escape sequences and flush
    max_out += 16 if @to.stateful
    dst = Bytes.new(max_out)
    src_consumed, dst_written = convert(input, dst)
    dst_written += flush_encoder(dst, dst_written)

    if src_consumed < input.size
      unless @flags.ignore?
        raise CharConv::ConversionError.new(
          "Conversion failed at byte #{src_consumed} (#{src_consumed}/#{input.size} bytes consumed)"
        )
      end
      # With //IGNORE, trailing incomplete sequences are silently discarded
    end
    dst[0, dst_written]
  end

  # IO streaming: reads from input, converts, writes to output.
  # Handles partial consumption, multi-chunk processing, and stateful flush.
  def convert(input : IO, output : IO, buffer_size : Int32 = 8192)
    src_buf = Bytes.new(buffer_size)
    dst_buf = Bytes.new(buffer_size * @to.max_bytes_per_char.to_i32)
    src_len = 0

    loop do
      bytes_read = input.read(src_buf[src_len..])
      src_len += bytes_read
      at_eof = bytes_read == 0

      break if src_len == 0 && at_eof

      src = src_buf[0, src_len]
      consumed, written = convert(src, dst_buf)
      output.write(dst_buf[0, written]) if written > 0

      remaining = src_len - consumed
      if remaining > 0
        if at_eof
          # Unconsumed bytes at EOF — incomplete sequence
          unless @flags.ignore?
            raise CharConv::ConversionError.new(
              "Incomplete sequence at end of input (#{remaining} byte(s) remaining)"
            )
          end
          break
        end
        (src_buf.to_unsafe + consumed).copy_to(src_buf.to_unsafe, remaining) if consumed > 0
      end
      src_len = remaining

      break if at_eof
    end

    # Flush stateful encoders
    flush_written = flush_encoder(dst_buf, 0)
    output.write(dst_buf[0, flush_written]) if flush_written > 0
  end

  # Flush stateful encoder state to dst. Returns bytes written.
  def flush_encoder(dst : Bytes, pos : Int32) : Int32
    if @to.id.utf7? && @state_encode.mode == 2_u8
      Codec::UTF7.flush_base64(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_jp? || @to.id.iso2022_jp1? || @to.id.iso2022_jp2?
      Codec::ISO2022JP.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_cn? || @to.id.iso2022_cn_ext?
      Codec::ISO2022CN.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_kr?
      Codec::ISO2022KR.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.hz?
      Codec::HZ.flush(dst, pos, pointerof(@state_encode))
    else
      0
    end
  end

  def reset
    @state_decode.reset
    @state_encode.reset
    init_codec_modes
  end
end
