require "./iconvcr/types"
require "./iconvcr/decode"
require "./iconvcr/encode"
require "./iconvcr/tables/single_byte"
require "./iconvcr/tables/table_index"
require "./iconvcr/codecs/utf16"
require "./iconvcr/codecs/utf32"
require "./iconvcr/codecs/utf7"
require "./iconvcr/codecs/c99"
require "./iconvcr/tables/cjk_jis"
require "./iconvcr/tables/cjk_gb"
require "./iconvcr/tables/cjk_big5"
require "./iconvcr/tables/cjk_ksc"
require "./iconvcr/tables/cjk_euctw"
require "./iconvcr/tables/gb18030_ranges"
require "./iconvcr/codecs/cjk"
require "./iconvcr/codecs/gb18030"
require "./iconvcr/codecs/iso2022_jp"
require "./iconvcr/codecs/iso2022_cn"
require "./iconvcr/codecs/iso2022_kr"
require "./iconvcr/codecs/hz"
require "./iconvcr/registry"
require "./iconvcr/transliteration"
require "./iconvcr/converter"

module Iconvcr
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
