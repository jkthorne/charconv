require "./spec_helper"

# FFI to system iconv for comparison
lib LibC
  fun iconv_open(tocode : LibC::Char*, fromcode : LibC::Char*) : LibC::IconvT
  fun iconv(cd : LibC::IconvT, inbuf : LibC::Char**, inbytesleft : LibC::SizeT*, outbuf : LibC::Char**, outbytesleft : LibC::SizeT*) : LibC::SizeT
  fun iconv_close(cd : LibC::IconvT) : LibC::Int
end

def sys_iconv_one(cd : LibC::IconvT, input : Bytes) : Bytes?
  # Reset
  LibC.iconv(cd, Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null,
             Pointer(LibC::Char*).null, Pointer(LibC::SizeT).null)

  out_buf = Bytes.new(16)
  in_ptr = input.to_unsafe.as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(LibC::Char*)
  out_left = LibC::SizeT.new(out_buf.size)

  result = LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  if result == ~LibC::SizeT.new(0) || in_left != 0
    nil
  else
    written = out_buf.size - out_left
    out_buf[0, written]
  end
end

CJK_DECODE_TESTS = [
  # {encoding_name, lead_min, lead_max, trail_min, trail_max}
  {"EUC-JP", 0xA1, 0xFE, 0xA1, 0xFE},
  {"SHIFT_JIS", 0x81, 0xEF, 0x40, 0xFC},
  {"CP932", 0x81, 0xFC, 0x40, 0xFC},
  {"GBK", 0x81, 0xFE, 0x40, 0xFE},
  {"EUC-CN", 0xA1, 0xF7, 0xA1, 0xFE},
  {"BIG5", 0x81, 0xFE, 0x40, 0xFE},
  {"CP950", 0x81, 0xFE, 0x40, 0xFE},
  {"EUC-KR", 0xA1, 0xFE, 0xA1, 0xFE},
  {"CP949", 0x81, 0xFE, 0x41, 0xFE},
]

describe "CJK exhaustive decode comparison" do
  CJK_DECODE_TESTS.each do |encoding, lead_min, lead_max, trail_min, trail_max|
    it "#{encoding} 2-byte decode matches system iconv for all (lead, trail) pairs" do
      cd_sys = LibC.iconv_open("UTF-8", encoding)
      next if cd_sys.address == ~LibC::SizeT.new(0)

      converter = CharConv::Converter.new(encoding, "UTF-8")
      mismatches = 0
      first_mismatch = ""

      (lead_min..lead_max).each do |lead|
        (trail_min..trail_max).each do |trail|
          input = Bytes[lead.to_u8, trail.to_u8]

          # System iconv result
          sys_result = sys_iconv_one(cd_sys, input)

          # Our result
          dst = Bytes.new(16)
          converter.reset
          src_consumed, dst_written = converter.convert(input, dst)

          if sys_result
            # System iconv succeeded — check if our output matches
            our_out = dst[0, dst_written]
            if our_out != sys_result
              # For encodings with single-byte ranges in the lead space (e.g., Shift_JIS katakana),
              # system iconv may consume byte 1 as single-byte and byte 2 separately.
              # Only count as mismatch if we consumed the same number of bytes but produced different output.
              if src_consumed == 2
                mismatches += 1
                if first_mismatch.empty?
                  first_mismatch = "0x#{lead.to_s(16).upcase}#{trail.to_s(16).upcase}: expected #{sys_result.map { |b| "%02X" % b }.join}, got #{our_out.map { |b| "%02X" % b }.join} (consumed #{src_consumed})"
                end
              end
              # If we consumed <2, system iconv may have consumed both as separate characters — skip
            end
          else
            # System iconv failed — we should fail too (or consume less than 2)
            if src_consumed == 2
              mismatches += 1
              if first_mismatch.empty?
                first_mismatch = "0x#{lead.to_s(16).upcase}#{trail.to_s(16).upcase}: system iconv failed but we produced #{dst_written} bytes"
              end
            end
          end
        end
      end

      LibC.iconv_close(cd_sys)
      mismatches.should eq(0), "#{encoding}: #{mismatches} pair(s) differ. First: #{first_mismatch}"
    end
  end
end
