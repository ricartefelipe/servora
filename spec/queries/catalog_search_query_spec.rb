# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogSearchQuery do
  let(:organization) { create(:organization) }

  before do
    create(:catalog_item, organization:, name: "Limpeza", sku: "SRV-01")
    create(:catalog_item, :part, organization:, name: "Capacitor", sku: "PEC-9")
    create(:catalog_item, organization:, name: "Serviço antigo", active: false)
  end

  def names(**filters)
    in_tenant(organization) { described_class.new(CatalogItem.all, **filters).call.map(&:name) }
  end

  it "filters by kind, activity and name or code" do
    expect(names).to eq(%w[Capacitor Limpeza])
    expect(names(kind: "part")).to eq(["Capacitor"])
    expect(names(include_inactive: true)).to include("Serviço antigo")
    expect(names(term: "srv")).to eq(["Limpeza"])
  end
end
