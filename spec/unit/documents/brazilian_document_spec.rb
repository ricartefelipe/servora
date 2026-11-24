# frozen_string_literal: true

RSpec.describe Documents::BrazilianDocument do
  describe ".kind" do
    it "recognizes a valid CPF with or without punctuation" do
      expect(described_class.kind("529.982.247-25")).to eq(:cpf)
      expect(described_class.kind("52998224725")).to eq(:cpf)
    end

    it "recognizes a valid numeric CNPJ" do
      expect(described_class.kind("11.222.333/0001-81")).to eq(:cnpj)
    end

    it "recognizes the alphanumeric CNPJ format" do
      expect(described_class.kind("12.ABC.345/01DE-35")).to eq(:cnpj)
      expect(described_class.kind("12abc34501de35")).to eq(:cnpj)
    end

    it "rejects wrong check digits" do
      expect(described_class.kind("529.982.247-24")).to be_nil
      expect(described_class.kind("11.222.333/0001-82")).to be_nil
      expect(described_class.kind("12.ABC.345/01DE-36")).to be_nil
    end

    it "rejects repeated digits and malformed values" do
      expect(described_class.kind("111.111.111-11")).to be_nil
      expect(described_class.kind("00000000000000")).to be_nil
      expect(described_class.kind("123")).to be_nil
      expect(described_class.kind(nil)).to be_nil
    end
  end

  describe ".format" do
    it "formats CPF and CNPJ" do
      expect(described_class.format("52998224725")).to eq("529.982.247-25")
      expect(described_class.format("11222333000181")).to eq("11.222.333/0001-81")
      expect(described_class.format("12abc34501de35")).to eq("12.ABC.345/01DE-35")
    end

    it "returns invalid input unchanged" do
      expect(described_class.format("abc")).to eq("abc")
    end
  end
end
