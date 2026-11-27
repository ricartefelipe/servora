# frozen_string_literal: true

RSpec.describe Documents::BrazilianPhone do
  describe ".format" do
    it "masks mobile and landline numbers with area code" do
      expect(described_class.format("11987412035")).to eq("(11) 98741-2035")
      expect(described_class.format("1133334444")).to eq("(11) 3333-4444")
      expect(described_class.format("(51) 3221.0099")).to eq("(51) 3221-0099")
    end

    it "drops the country code and the trunk prefix" do
      expect(described_class.format("+55 11 98741-2035")).to eq("(11) 98741-2035")
      expect(described_class.format("551133334444")).to eq("(11) 3333-4444")
      expect(described_class.format("011 98741 2035")).to eq("(11) 98741-2035")
      expect(described_class.format("01133334444")).to eq("(11) 3333-4444")
    end

    it "keeps area code 55 numbers intact" do
      expect(described_class.format("55991234567")).to eq("(55) 99123-4567")
    end

    it "masks numbers without area code and non-geographic numbers" do
      expect(described_class.format("987412035")).to eq("98741-2035")
      expect(described_class.format("33334444")).to eq("3333-4444")
      expect(described_class.format("0800 777 1234")).to eq("0800 777 1234")
      expect(described_class.format("08007771234")).to eq("0800 777 1234")
    end

    it "shows anything else as typed" do
      expect(described_class.format("+1 415 555 0100")).to eq("+1 415 555 0100")
      expect(described_class.format(" 190 ")).to eq("190")
      expect(described_class.format("ramal 22")).to eq("ramal 22")
      expect(described_class.format(nil)).to eq("")
    end
  end
end
