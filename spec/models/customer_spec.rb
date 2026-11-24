# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer do
  it "requires a CPF for individuals and a CNPJ for companies" do
    individual = build(:customer, :individual, document: "11.222.333/0001-81")
    company = build(:customer, document: "529.982.247-25")

    expect(individual).not_to be_valid
    expect(individual.errors[:document]).to include("deve ser um CPF válido")
    expect(company).not_to be_valid
    expect(company.errors[:document]).to include("deve ser um CNPJ válido")
  end

  it "keeps the document unique inside the organization only" do
    first = create(:customer, document: "11222333000181")
    duplicate = build(:customer, organization: first.organization, document: "11.222.333/0001-81")
    other_tenant = build(:customer, organization: create(:organization), document: "11222333000181")

    expect(in_tenant(first.organization) { duplicate.valid? }).to be(false)
    expect(in_tenant(other_tenant.organization) { other_tenant.valid? }).to be(true)
  end

  it "uses the trade name for display" do
    expect(build(:customer, name: "Alfa Comércio Ltda.", trade_name: "Loja Alfa").display_name).to eq("Loja Alfa")
  end
end
