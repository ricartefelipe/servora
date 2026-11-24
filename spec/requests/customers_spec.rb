# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customers, locations and contacts" do
  let(:organization) { create(:organization) }
  let(:attendant) { create(:membership, :attendant, organization:) }
  let(:customer) { create(:customer, organization:, name: "Padaria Pão Quente") }

  before { create(:service_location, customer:) }

  it "searches customers with bound parameters" do
    create(:customer, organization:, name: "Oficina Rápida")
    sign_in_as(attendant)

    get customers_path, params: { q: "Pão' OR 1=1 --" }
    expect(response.body).not_to include("Padaria Pão Quente")

    get customers_path, params: { q: "padaria" }
    expect(response.body).to include("Padaria Pão Quente")
    expect(response.body).not_to include("Oficina Rápida")
  end

  it "creates a customer with its first location" do
    sign_in_as(attendant)

    post customers_path, params: { customer: { kind: "individual", name: "Joana Prado", document: "529.982.247-25",
                                               location_name: "Residência", street: "Rua A", city: "Recife", state: "PE" } }

    customer = in_tenant(organization) { Customer.find_by!(name: "Joana Prado") }
    expect(response).to redirect_to(customer_path(customer))
  end

  it "renders validation errors inside the modal through Turbo Streams" do
    sign_in_as(attendant)

    post customer_locations_path(customer), params: { service_location: { name: "", street: "", city: "", state: "" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('target="modal-body"', "Revise os campos destacados")
  end

  it "adds a contact allowed to approve quotes" do
    sign_in_as(attendant)

    post customer_contacts_path(customer),
      params: { customer_contact: { name: "Rui", email: "rui@padaria.test", can_approve: "1" } }

    expect(in_tenant(organization) { customer.contacts.sole }).to have_attributes(name: "Rui", can_approve: true)
  end

  it "archives and restores customers with permission" do
    sign_in_as(attendant)

    patch archive_customer_path(customer)
    expect(in_tenant(organization) { customer.reload.archived? }).to be(true)
    get edit_customer_path(customer)
    expect(response).to have_http_status(:forbidden)

    patch restore_customer_path(customer)
    expect(in_tenant(organization) { customer.reload.archived? }).to be(false)
  end

  it "hides customers from technicians and from other organizations" do
    sign_in_as(create(:membership, :technician, organization:))
    get customers_path
    expect(response).to have_http_status(:forbidden)

    sign_in_as(create(:membership, :owner))
    get customer_path(customer)
    expect(response).to have_http_status(:not_found)
  end

  it "detects concurrent edits with optimistic locking" do
    sign_in_as(attendant)
    stale = in_tenant(organization) { customer.lock_version }
    in_tenant(organization) { customer.update!(phone: "1199999") }

    patch customer_path(customer), params: { customer: { name: "Novo nome", lock_version: stale } }

    expect(response).to redirect_to(edit_customer_path(customer))
    expect(in_tenant(organization) { customer.reload.name }).to eq("Padaria Pão Quente")
  end
end
