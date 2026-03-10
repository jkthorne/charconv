require "./spec_helper"

describe CharConv do
  describe ".encoding_supported?" do
    it "returns true for known encodings" do
      CharConv.encoding_supported?("UTF-8").should be_true
      CharConv.encoding_supported?("ASCII").should be_true
      CharConv.encoding_supported?("ISO-8859-1").should be_true
    end

    it "handles aliases and normalization" do
      CharConv.encoding_supported?("utf-8").should be_true
      CharConv.encoding_supported?("US-ASCII").should be_true
      CharConv.encoding_supported?("Latin1").should be_true
      CharConv.encoding_supported?("ANSI_X3.4-1968").should be_true
    end

    it "strips //IGNORE and //TRANSLIT suffixes" do
      CharConv.encoding_supported?("UTF-8//IGNORE").should be_true
      CharConv.encoding_supported?("ASCII//TRANSLIT").should be_true
    end

    it "returns false for unknown encodings" do
      CharConv.encoding_supported?("EBCDIC").should be_false
      CharConv.encoding_supported?("").should be_false
    end
  end

  describe ".list_encodings" do
    it "returns canonical encoding names" do
      names = CharConv.list_encodings
      names.should contain("ASCII")
      names.should contain("UTF-8")
      names.should contain("ISO-8859-1")
    end
  end

  describe ".convert" do
    it "converts a simple ASCII string" do
      result = CharConv.convert("hello", "UTF-8", "ASCII")
      result.should eq("hello".to_slice)
    end

    it "converts UTF-8 string to ISO-8859-1" do
      result = CharConv.convert("café", "UTF-8", "ISO-8859-1")
      result.should eq(Bytes[99, 97, 102, 0xE9])
    end

    it "converts Bytes input" do
      input = Bytes[0xE9] # é in ISO-8859-1
      result = CharConv.convert(input, "ISO-8859-1", "UTF-8")
      result.should eq(Bytes[0xC3, 0xA9])
    end

    it "raises on unknown encoding" do
      expect_raises(ArgumentError) do
        CharConv.convert("test", "EBCDIC", "UTF-8")
      end
    end
  end
end
