module Iconvcr::Registry
  private ASCII_INFO     = EncodingInfo.new(EncodingID::ASCII, true, 1_u8, false)
  private UTF8_INFO      = EncodingInfo.new(EncodingID::UTF8, true, 4_u8, false)
  private ISO_8859_1_INFO = EncodingInfo.new(EncodingID::ISO_8859_1, true, 1_u8, false)

  ENCODINGS = {
    "ASCII"        => ASCII_INFO,
    "USASCII"      => ASCII_INFO,
    "ANSIX341968"  => ASCII_INFO,
    "ISO646US"     => ASCII_INFO,
    "UTF8"         => UTF8_INFO,
    "ISO88591"     => ISO_8859_1_INFO,
    "LATIN1"       => ISO_8859_1_INFO,
    "ISO885911987"  => ISO_8859_1_INFO,
  }

  CANONICAL_NAMES = ["ASCII", "UTF-8", "ISO-8859-1"]

  def self.normalize(name : String) : String
    String.build(name.size) do |io|
      name.each_char do |c|
        if c.ascii_alphanumeric?
          io << c.upcase
        end
      end
    end
  end

  def self.lookup(name : String) : EncodingInfo?
    # Strip //IGNORE and //TRANSLIT suffixes
    clean = name
    if idx = clean.index("//")
      clean = clean[0...idx]
    end
    normalized = normalize(clean)
    ENCODINGS[normalized]?
  end

  def self.canonical_names : Array(String)
    CANONICAL_NAMES.dup
  end
end
