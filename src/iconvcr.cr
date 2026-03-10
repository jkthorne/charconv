require "./iconvcr/types"
require "./iconvcr/decode"
require "./iconvcr/encode"
require "./iconvcr/registry"
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

  def self.encoding_supported?(name : String) : Bool
    !Registry.lookup(name).nil?
  end

  def self.list_encodings : Array(String)
    Registry.canonical_names
  end
end
