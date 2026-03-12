require "./charconv/types"
require "./charconv/decode"
require "./charconv/encode"
require "./charconv/tables/single_byte"
require "./charconv/tables/table_index"
require "./charconv/codecs/utf16"
require "./charconv/codecs/utf32"
require "./charconv/codecs/utf7"
require "./charconv/codecs/c99"
{% if flag?(:charconv_minimal) %}
  require "./charconv/codecs/cjk_stubs"
{% else %}
  require "./charconv/tables/cjk_jis"
  require "./charconv/tables/cjk_gb"
  require "./charconv/tables/cjk_big5"
  require "./charconv/tables/cjk_ksc"
  require "./charconv/tables/cjk_euctw"
  require "./charconv/tables/gb18030_ranges"
  require "./charconv/codecs/cjk"
  require "./charconv/codecs/gb18030"
  require "./charconv/codecs/iso2022_jp"
  require "./charconv/codecs/iso2022_cn"
  require "./charconv/codecs/iso2022_kr"
  require "./charconv/codecs/hz"
{% end %}
require "./charconv/registry"
require "./charconv/transliteration"
require "./charconv/converter"

module CharConv
  VERSION = "0.1.0"

  class ConversionError < Exception
  end

  def self.convert(input : Bytes, from : String, to : String) : Bytes
    converter = Converter.new(from, to)
    converter.convert(input)
  end

  def self.convert(input : String, from : String, to : String) : Bytes
    convert(input.to_slice, from, to)
  end

  def self.convert(input : IO, output : IO, from : String, to : String, buffer_size : Int32 = 8192)
    converter = Converter.new(from, to)
    converter.convert(input, output, buffer_size)
  end

  def self.encoding_supported?(name : String) : Bool
    !Registry.lookup(name).nil?
  end

  def self.list_encodings : Array(String)
    Registry.canonical_names
  end
end
