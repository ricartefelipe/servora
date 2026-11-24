# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::SearchQuery do
  let(:organization) { create(:organization) }

  before do
    create(:customer, organization:, name: "Alfa Refrigeração", document: "11222333000181", email: "alfa@x.test")
    create(:customer, organization:, name: "Beta Hotéis", trade_name: "Hotel Beta", archived_at: Time.current)
  end

  def names(**filters)
    in_tenant(organization) { described_class.new(Customer.all, **filters).call.map(&:name) }
  end

  it "filters by status, defaulting to active customers" do
    expect(names).to eq(["Alfa Refrigeração"])
    expect(names(status: "arquivados")).to eq(["Beta Hotéis"])
    expect(names(status: "todos")).to eq(["Alfa Refrigeração", "Beta Hotéis"])
    expect(names(status: "invalido")).to eq(["Alfa Refrigeração"])
  end

  it "matches trade names and document digits, treating wildcards literally" do
    expect(names(term: "hotel", status: "todos")).to eq(["Beta Hotéis"])
    expect(names(term: "11.222", status: "todos")).to eq(["Alfa Refrigeração"])
    expect(names(term: "%", status: "todos")).to be_empty
  end
end
