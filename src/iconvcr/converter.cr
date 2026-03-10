class Iconvcr::Converter
  getter from : EncodingInfo
  getter to : EncodingInfo

  def initialize(from_encoding : String, to_encoding : String)
    @from = Registry.lookup(from_encoding) || raise ArgumentError.new("Unknown encoding: #{from_encoding}")
    @to = Registry.lookup(to_encoding) || raise ArgumentError.new("Unknown encoding: #{to_encoding}")
    @state_decode = CodecState.new
    @state_encode = CodecState.new
  end

  # Scans a run of ASCII bytes using 8-byte word reads.
  # Returns the number of consecutive ASCII bytes starting at `from`.
  # Safe on Apple Silicon aarch64 — unaligned UInt64 reads have no penalty.
  @[AlwaysInline]
  private def scan_ascii_run(src : Bytes, from : Int32) : Int32
    pos = from
    remaining = src.size - pos

    # 8-byte word scan: check high bit of each byte via mask
    while remaining >= 8
      word = (src.to_unsafe + pos).as(Pointer(UInt64)).value
      break if word & 0x8080808080808080_u64 != 0
      pos += 8
      remaining -= 8
    end

    # Byte-at-a-time tail
    while pos < src.size
      break if src.unsafe_fetch(pos) >= 0x80_u8
      pos += 1
    end

    pos - from
  end

  @[AlwaysInline]
  private def decode_one(src : Bytes, pos : Int32) : DecodeResult
    case @from.id
    in EncodingID::ASCII      then Decode.ascii(src, pos)
    in EncodingID::UTF8       then Decode.utf8(src, pos)
    in EncodingID::ISO_8859_1 then Decode.iso_8859_1(src, pos)
    end
  end

  @[AlwaysInline]
  private def encode_one(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    case @to.id
    in EncodingID::ASCII      then Encode.ascii(cp, dst, pos)
    in EncodingID::UTF8       then Encode.utf8(cp, dst, pos)
    in EncodingID::ISO_8859_1 then Encode.iso_8859_1(cp, dst, pos)
    end
  end

  # Fast path for conversions where both encodings are ASCII supersets.
  # Scans ASCII runs and memcpys them, then decodes/encodes non-ASCII one char at a time.
  private def convert_ascii_fast(src : Bytes, dst : Bytes) : {Int32, Int32}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      # Scan ASCII run
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        # Both encodings are ASCII supersets, so ASCII bytes are identical
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        src.to_unsafe.copy_to(dst.to_unsafe + dst_pos, copy_len) if copy_len > 0
        # Adjust: we need to copy from the right offset
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        break if copy_len < ascii_len # output full
        next
      end

      # Non-ASCII character: decode then encode
      dr = decode_one(src, src_pos)
      if dr.status == -1 # ILSEQ
        return {src_pos, dst_pos}
      elsif dr.status == 0 # TOOFEW
        return {src_pos, dst_pos}
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1 # ILUNI
        return {src_pos, dst_pos}
      elsif er.status == 0 # TOOSMALL
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

  # Converts bytes from source encoding to destination encoding.
  # Returns {bytes_consumed, bytes_written}.
  # Stops at the first error or when buffers are exhausted.
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
    dst = Bytes.new(max_out)
    src_consumed, dst_written = convert(input, dst)
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
  end
end
