require "./spec_helper"
require "benchmark"

# Use Crystal's built-in LibC iconv bindings

private def bench_system_iconv(input : Bytes, from : String, to : String, out_buf : Bytes)
  cd = LibC.iconv_open(to, from)
  raise "iconv_open failed" if cd.address == LibC::SizeT::MAX

  in_ptr = input.to_unsafe.as(UInt8*).as(LibC::Char*)
  in_left = LibC::SizeT.new(input.size)
  out_ptr = out_buf.to_unsafe.as(UInt8*).as(LibC::Char*)
  out_left = LibC::SizeT.new(out_buf.size)

  LibC.iconv(cd, pointerof(in_ptr), pointerof(in_left), pointerof(out_ptr), pointerof(out_left))
  LibC.iconv_close(cd)
end

SIZE = 1_048_576 # 1 MB

def make_ascii_data : Bytes
  Bytes.new(SIZE) { |i| (0x20 + (i % 95)).to_u8 }
end

def make_mixed_latin_data : Bytes
  io = IO::Memory.new(SIZE)
  rng = Random.new(42)
  while io.pos < SIZE - 2
    if rng.rand < 0.8
      io.write_byte((0x20 + rng.rand(95)).to_u8)
    else
      cp = 0xA0 + rng.rand(96)
      io.write_byte((0xC0 | (cp >> 6)).to_u8)
      io.write_byte((0x80 | (cp & 0x3F)).to_u8)
    end
  end
  io.to_slice[0, Math.min(io.pos, SIZE)]
end

def make_iso_8859_1_data : Bytes
  Bytes.new(SIZE) { |i| (i % 256).to_u8 }
end

def make_utf8_data : Bytes
  io = IO::Memory.new(SIZE)
  rng = Random.new(42)
  while io.pos < SIZE - 4
    case rng.rand(4)
    when 0 then io.write_byte((0x20 + rng.rand(95)).to_u8)
    when 1
      cp = 0xA0 + rng.rand(96)
      io.write_byte((0xC0 | (cp >> 6)).to_u8)
      io.write_byte((0x80 | (cp & 0x3F)).to_u8)
    when 2
      cp = 0x4E00 + rng.rand(0x5000)
      io.write_byte((0xE0 | (cp >> 12)).to_u8)
      io.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_u8)
      io.write_byte((0x80 | (cp & 0x3F)).to_u8)
    else
      cp = 0x1F600 + rng.rand(80)
      io.write_byte((0xF0 | (cp >> 18)).to_u8)
      io.write_byte((0x80 | ((cp >> 12) & 0x3F)).to_u8)
      io.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_u8)
      io.write_byte((0x80 | (cp & 0x3F)).to_u8)
    end
  end
  io.to_slice[0, Math.min(io.pos, SIZE)]
end

describe "Benchmarks" do
  it "prints throughput comparison" do
    ascii_data = make_ascii_data
    mixed_latin = make_mixed_latin_data
    iso_data = make_iso_8859_1_data
    utf8_data = make_utf8_data

    out_4mb = Bytes.new(SIZE * 4)

    puts "\n" + "=" * 60
    puts "Throughput Benchmarks (1 MB input)"
    puts "=" * 60

    puts "\n--- ASCII → ASCII ---"
    conv = Iconvcr::Converter.new("ASCII", "ASCII")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(ascii_data, out_4mb) }
      x.report("system iconv") { bench_system_iconv(ascii_data, "ASCII", "ASCII", out_4mb) }
    end

    puts "\n--- UTF-8 → ISO-8859-1 (mixed Latin ~80% ASCII) ---"
    conv = Iconvcr::Converter.new("UTF-8", "ISO-8859-1")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(mixed_latin, out_4mb) }
      x.report("system iconv") { bench_system_iconv(mixed_latin, "UTF-8", "ISO-8859-1", out_4mb) }
    end

    puts "\n--- ISO-8859-1 → UTF-8 ---"
    conv = Iconvcr::Converter.new("ISO-8859-1", "UTF-8")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(iso_data, out_4mb) }
      x.report("system iconv") { bench_system_iconv(iso_data, "ISO-8859-1", "UTF-8", out_4mb) }
    end

    puts "\n--- UTF-8 → UTF-8 (mixed widths) ---"
    conv = Iconvcr::Converter.new("UTF-8", "UTF-8")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(utf8_data, out_4mb) }
      x.report("system iconv") { bench_system_iconv(utf8_data, "UTF-8", "UTF-8", out_4mb) }
    end

    # Phase 2: single-byte encoding benchmarks
    # CP1252 valid bytes (exclude undefined: 0x81, 0x8D, 0x8F, 0x90, 0x9D)
    cp1252_valid = (0x00..0xFF).to_a.reject { |b| {0x81, 0x8D, 0x8F, 0x90, 0x9D}.includes?(b) }
    cp1252_data = Bytes.new(SIZE) { |i| cp1252_valid[i % cp1252_valid.size].to_u8 }

    puts "\n--- CP1252 → UTF-8 ---"
    conv = Iconvcr::Converter.new("CP1252", "UTF-8")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(cp1252_data, out_4mb) }
      x.report("system iconv") { bench_system_iconv(cp1252_data, "CP1252", "UTF-8", out_4mb) }
    end

    puts "\n--- UTF-8 → CP1252 (mixed Latin ~80% ASCII) ---"
    conv = Iconvcr::Converter.new("UTF-8", "CP1252")
    Benchmark.ips do |x|
      x.report("iconvcr") { conv.convert(mixed_latin, out_4mb) }
      x.report("system iconv") { bench_system_iconv(mixed_latin, "UTF-8", "CP1252", out_4mb) }
    end

    puts "\n" + "=" * 60
  end
end
