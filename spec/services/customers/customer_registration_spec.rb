# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerRegistration do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, organization:) }
  let(:valid_attributes) do
    { kind: "company", name: "Mercado Bom Preço Ltda.", document: "11.222.333/0001-81", location_name: "Loja Centro",
      street: "Rua XV de Novembro", number: "200", city: "Curitiba", state: "PR", postal_code: "80020-310",
      contact_name: "Marta Silva", contact_email: "marta@bompreco.test", contact_can_approve: true }
  end

  it "creates customer, first location and contact in one transaction" do
    form = described_class.new(valid_attributes)

    expect(as_member(owner) { form.save(organization:) }).to be(true)

    in_tenant(organization) do
      customer = Customer.includes(:service_locations, :contacts).sole
      expect(customer.service_locations.map(&:name)).to eq(["Loja Centro"])
      expect(customer.contacts.sole).to have_attributes(name: "Marta Silva", can_approve: true)
      expect(customer.service_locations.sole.postal_code).to eq("80020310")
    end
  end

  it "reports errors of every part and persists nothing" do
    form = described_class.new(valid_attributes.merge(name: "", state: "ZZ", contact_email: "invalido"))

    expect(as_member(owner) { form.save(organization:) }).to be(false)
    expect(form.errors.attribute_names).to include(:name, :state, :contact_email)
    expect(in_tenant(organization) { Customer.count }).to eq(0)
  end
end
