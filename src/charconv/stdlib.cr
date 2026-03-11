# Replace Crystal's libiconv usage with CharConv.
#
# When this file is required, all stdlib encoding operations (String#encode,
# String.new(bytes, encoding), IO#set_encoding) use the pure-Crystal charconv
# implementation.
#
# Two modes:
#   - Default: monkey-patches Crystal::Iconv. libiconv is still linked but
#     never called at runtime.
#   - With `-Dwithout_iconv`: defines Crystal::Iconv from scratch and provides
#     real IO::Encoder/IO::Decoder implementations. No libiconv dependency at all.
#
# Usage:
#   require "charconv/stdlib"
#
#   "café".encode("ISO-8859-1")  # uses charconv, not libiconv

require "../charconv"

# Shared module with the charconv-backed iconv implementation.
# Used by both the monkey-patch path and the without_iconv path.
module CharConv::StdlibBridge
  # Create a CharConv::Converter from iconv-style encoding names.
  # Strips //IGNORE from `from` (charconv applies IGNORE from the `to` flags).
  # Returns {converter, skip_invalid}.
  def self.create_converter(from : String, to : String, invalid : Symbol? = nil) : {CharConv::Converter, Bool}
    skip_invalid = (invalid == :skip)
    clean_from = from.gsub("//IGNORE", "")

    to_enc = to
    {% unless flag?(:freebsd) || flag?(:musl) || flag?(:dragonfly) || flag?(:netbsd) || flag?(:solaris) %}
      if skip_invalid && !to_enc.includes?("//IGNORE")
        to_enc = "#{to_enc}//IGNORE"
      end
    {% end %}

    original_from = clean_from.gsub("//IGNORE", "").gsub("//TRANSLIT", "")
    original_to = to.gsub("//IGNORE", "").gsub("//TRANSLIT", "")

    begin
      converter = CharConv::Converter.new(clean_from, to_enc)
    rescue ex : ArgumentError
      if original_from == "UTF-8"
        raise ArgumentError.new("Invalid encoding: #{original_to}")
      elsif original_to == "UTF-8"
        raise ArgumentError.new("Invalid encoding: #{original_from}")
      else
        raise ArgumentError.new("Invalid encoding: #{original_from} -> #{original_to}")
      end
    end

    {converter, skip_invalid}
  end

  # Bridge from iconv pointer-advancing API to CharConv slice API.
  def self.convert(converter : CharConv::Converter,
                   inbuf : UInt8**, inbytesleft : LibC::SizeT*,
                   outbuf : UInt8**, outbytesleft : LibC::SizeT*,
                   error_value : LibC::SizeT) : LibC::SizeT
    # NULL inbuf = flush stateful encoder and reset
    if inbuf.null?
      dst = Bytes.new(outbuf.value, outbytesleft.value)
      written = converter.flush_encoder(dst, 0)
      outbuf.value += written
      outbytesleft.value -= written
      converter.reset
      return LibC::SizeT.new(0)
    end

    src = Bytes.new(inbuf.value, inbytesleft.value)
    dst = Bytes.new(outbuf.value, outbytesleft.value)

    consumed, written, status = converter.convert_with_status(src, dst)

    inbuf.value += consumed
    inbytesleft.value -= consumed
    outbuf.value += written
    outbytesleft.value -= written

    case status
    in .ok?
      LibC::SizeT.new(0)
    in .e2_big?
      Errno.value = Errno::E2BIG
      error_value
    in .eilseq?
      Errno.value = Errno::EILSEQ
      error_value
    in .einval?
      Errno.value = Errno::EINVAL
      error_value
    end
  end

  def self.handle_invalid(skip_invalid : Bool, inbuf, inbytesleft) : Nil
    if skip_invalid
      if inbytesleft.value > 0
        inbuf.value += 1
        inbytesleft.value -= 1
      end
    else
      case Errno.value
      when Errno::EINVAL
        raise ArgumentError.new "Incomplete multibyte sequence"
      when Errno::EILSEQ
        raise ArgumentError.new "Invalid multibyte sequence"
      end
    end
  end
end

{% if flag?(:without_iconv) %}

  # ── without_iconv path ──────────────────────────────────────────────────
  # Crystal::Iconv doesn't exist. Define it from scratch so String#encode
  # and String.new(bytes, encoding) work. Also provide real IO::Encoder and
  # IO::Decoder to replace the NotImplementedError stubs.

  struct Crystal::Iconv
    ERROR = LibC::SizeT::MAX

    @skip_invalid : Bool
    @converter : CharConv::Converter

    def initialize(from : String, to : String, invalid : Symbol? = nil)
      @converter, @skip_invalid = CharConv::StdlibBridge.create_converter(from, to, invalid)
    end

    def self.new(from : String, to : String, invalid : Symbol? = nil, &)
      iconv = new(from, to, invalid)
      begin
        yield iconv
      ensure
        iconv.close
      end
    end

    def convert(inbuf : UInt8**, inbytesleft : LibC::SizeT*, outbuf : UInt8**, outbytesleft : LibC::SizeT*)
      CharConv::StdlibBridge.convert(@converter, inbuf, inbytesleft, outbuf, outbytesleft, ERROR)
    end

    def handle_invalid(inbuf, inbytesleft)
      CharConv::StdlibBridge.handle_invalid(@skip_invalid, inbuf, inbytesleft)
    end

    def close
    end
  end

  # Replace the NotImplementedError stubs from encoding_stubs.cr with real
  # implementations. These are copied from Crystal's io/encoding.cr but use
  # our Crystal::Iconv backed by CharConv.
  class IO
    private class Encoder
      @encoding_options : EncodingOptions
      @iconv : Crystal::Iconv
      @closed : Bool

      def initialize(@encoding_options : EncodingOptions)
        @iconv = Crystal::Iconv.new("UTF-8", encoding_options.name, encoding_options.invalid)
        @closed = false
      end

      def write(io : IO, slice : Bytes) : Nil
        inbuf_ptr = slice.to_unsafe
        inbytesleft = LibC::SizeT.new(slice.size)
        outbuf = uninitialized UInt8[1024]
        while inbytesleft > 0
          outbuf_ptr = outbuf.to_unsafe
          outbytesleft = LibC::SizeT.new(outbuf.size)
          err = @iconv.convert(pointerof(inbuf_ptr), pointerof(inbytesleft), pointerof(outbuf_ptr), pointerof(outbytesleft))
          if err == Crystal::Iconv::ERROR
            @iconv.handle_invalid(pointerof(inbuf_ptr), pointerof(inbytesleft))
          end
          io.write(outbuf.to_slice[0, outbuf.size - outbytesleft])
        end
      end

      def close : Nil
        return if @closed
        @closed = true
        @iconv.close
      end

      def finalize : Nil
        close
      end
    end

    private class Decoder
      BUFFER_SIZE     = 4 * 1024
      OUT_BUFFER_SIZE = 4 * 1024

      property out_slice : Bytes

      @encoding_options : EncodingOptions
      @iconv : Crystal::Iconv
      @buffer : Bytes
      @in_buffer : Pointer(UInt8)
      @in_buffer_left : LibC::SizeT
      @out_buffer : Bytes
      @closed : Bool

      def initialize(@encoding_options : EncodingOptions)
        @iconv = Crystal::Iconv.new(encoding_options.name, "UTF-8", encoding_options.invalid)
        @buffer = Bytes.new((GC.malloc_atomic(BUFFER_SIZE).as(UInt8*)), BUFFER_SIZE)
        @in_buffer = @buffer.to_unsafe
        @in_buffer_left = LibC::SizeT.new(0)
        @out_buffer = Bytes.new((GC.malloc_atomic(OUT_BUFFER_SIZE).as(UInt8*)), OUT_BUFFER_SIZE)
        @out_slice = Bytes.empty
        @closed = false
      end

      def read(io : IO) : Nil
        loop do
          return unless @out_slice.empty?

          if @in_buffer_left == 0
            @in_buffer = @buffer.to_unsafe
            @in_buffer_left = LibC::SizeT.new(io.read(@buffer))
          end

          break if @in_buffer_left == 0

          out_buffer = @out_buffer.to_unsafe
          out_buffer_left = LibC::SizeT.new(OUT_BUFFER_SIZE)
          result = @iconv.convert(pointerof(@in_buffer), pointerof(@in_buffer_left), pointerof(out_buffer), pointerof(out_buffer_left))
          @out_slice = @out_buffer[0, OUT_BUFFER_SIZE - out_buffer_left]

          if result == Crystal::Iconv::ERROR
            case Errno.value
            when Errno::EILSEQ
              @iconv.handle_invalid(pointerof(@in_buffer), pointerof(@in_buffer_left))
            when Errno::EINVAL
              old_in_buffer_left = @in_buffer_left
              refill_in_buffer(io)
              if old_in_buffer_left == @in_buffer_left
                @iconv.handle_invalid(pointerof(@in_buffer), pointerof(@in_buffer_left))
              end
            end
            next
          end

          break
        end
      end

      private def refill_in_buffer(io)
        buffer_remaining = BUFFER_SIZE - @in_buffer_left - (@in_buffer - @buffer.to_unsafe)
        if buffer_remaining < 64
          @buffer.copy_from(@in_buffer, @in_buffer_left)
          @in_buffer = @buffer.to_unsafe
          buffer_remaining = BUFFER_SIZE - @in_buffer_left
        end
        @in_buffer_left += LibC::SizeT.new(io.read(Slice.new(@in_buffer + @in_buffer_left, buffer_remaining)))
      end

      def read_byte(io : IO) : UInt8?
        read(io)
        if out_slice.empty?
          nil
        else
          byte = out_slice.to_unsafe.value
          advance 1
          byte
        end
      end

      def read_utf8(io : IO, slice : Bytes) : Int32
        count = 0
        until slice.empty?
          read(io)
          break if out_slice.empty?

          available = Math.min(out_slice.size, slice.size)
          out_slice[0, available].copy_to(slice.to_unsafe, available)
          advance(available)
          count += available
          slice += available
        end
        count
      end

      def gets(io : IO, delimiter : UInt8, limit : Int, chomp : Bool) : String?
        read(io)
        return nil if @out_slice.empty?

        index = @out_slice.index(delimiter)
        if index
          if index >= limit
            index = limit
          else
            index += 1
          end
          return gets_index(index, delimiter, chomp)
        end

        if @out_slice.size >= limit
          return gets_index(limit, delimiter, chomp)
        end

        String.build do |str|
          loop do
            limit -= @out_slice.size
            write str

            read(io)

            break if @out_slice.empty?

            index = @out_slice.index(delimiter)
            if index
              if index >= limit
                index = limit
              else
                index += 1
              end
              write str, index
              break
            else
              if limit < @out_slice.size
                write(str, limit)
                break
              end
            end
          end
          str.chomp!(delimiter) if chomp
        end
      end

      private def gets_index(index, delimiter, chomp)
        advance_increment = index

        if chomp && index > 0 && @out_slice[index - 1] === delimiter
          index -= 1

          if delimiter === '\n' && index > 0 && @out_slice[index - 1] === '\r'
            index -= 1
          end
        end

        string = String.new(@out_slice[0, index])
        advance(advance_increment)
        string
      end

      def write(io : IO) : Nil
        io.write @out_slice
        @out_slice = Bytes.empty
      end

      def write(io : IO, numbytes : Int) : Nil
        io.write @out_slice[0, numbytes]
        @out_slice += numbytes
      end

      def advance(numbytes : Int) : Nil
        @out_slice += numbytes
      end

      def close : Nil
        return if @closed
        @closed = true
        @iconv.close
      end

      def finalize : Nil
        close
      end
    end
  end

{% else %}

  # ── Default path (libiconv is linked but not called) ────────────────────
  # Monkey-patch the existing Crystal::Iconv to delegate to CharConv.

  struct Crystal::Iconv
    @charconv : CharConv::Converter?

    def initialize(from : String, to : String, invalid : Symbol? = nil)
      converter, @skip_invalid = CharConv::StdlibBridge.create_converter(from, to, invalid)
      @charconv = converter

      # Satisfy the original @iconv field with a null pointer. This field is
      # never read — all access goes through the methods we override.
      @iconv = Pointer(Void).null.as(typeof(@iconv))
    end

    def convert(inbuf : UInt8**, inbytesleft : LibC::SizeT*, outbuf : UInt8**, outbytesleft : LibC::SizeT*)
      CharConv::StdlibBridge.convert(@charconv.not_nil!, inbuf, inbytesleft, outbuf, outbytesleft, ERROR)
    end

    def handle_invalid(inbuf, inbytesleft)
      CharConv::StdlibBridge.handle_invalid(@skip_invalid, inbuf, inbytesleft)
    end

    def close
      @charconv = nil
    end
  end

{% end %}
