# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Quotes" do
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }

  it "creates a quote, adds catalog and free items and sends it" do
    item = create(:catalog_item, organization:, name: "Carga de gás R410A", unit_price: BigDecimal("380.00"))
    sign_in_as(scenario[:author])

    post quotes_path, params: { quote: { service_location_id: scenario[:location].id, title: "Recarga" } }
    quote = in_tenant(organization) { Quote.sole }
    post quote_items_path(quote), params: { item: { catalog_item_id: item.id, quantity: "1" } }
    post quote_items_path(quote),
      params: { item: { description: "Deslocamento", kind: "other", unit: "vb", quantity: "1", unit_price: "60" } }
    post send_version_quote_path(quote)

    in_tenant(organization) do
      expect(quote.reload).to have_attributes(status: "sent")
      expect(quote.current_version.total).to eq(BigDecimal("440.00"))
    end
    get quote_path(quote)
    expect(response.body).to include("Conteúdo congelado", "Carga de gás R410A")
  end

  it "shows costs and margin only to roles allowed to see costs" do
    quote = create_quote(scenario)
    sign_in_as(scenario[:author])
    get quote_path(quote)
    expect(response.body).not_to include("Custo estimado")

    sign_in_as(create(:membership, :finance, organization:))
    get quote_path(quote)
    expect(response.body).to include("Custo estimado")
  end

  it "registers a decision communicated by phone with the registering member" do
    quote = create_quote(scenario)
    version = send_quote(scenario, quote)
    sign_in_as(scenario[:author])

    post quote_decisions_path(quote), params: { decision: { version_id: version.id, content_digest: version.content_digest,
                                                            contact_id: scenario[:approver].id, channel: "phone",
                                                            outcome: "approved", note: "Ligação às 10h" } }

    expect(in_tenant(organization) { version.reload }).to have_attributes(status: "approved", decision_channel: "phone",
      decided_by_membership_id: scenario[:author].id)
  end

  it "keeps the catalog cost out of reach of roles without the cost permission" do
    item = create(:catalog_item, organization:, unit_cost: BigDecimal("10"))
    sign_in_as(create(:membership, :coordinator, organization:))

    patch catalog_item_path(item), params: { catalog_item: { unit_cost: "999", unit_price: "300" } }
    get catalog_items_path

    expect(in_tenant(organization) { item.reload }).to have_attributes(unit_cost: BigDecimal("10"), unit_price: BigDecimal("300"))
    expect(response.body).not_to include(">Custo</th>")
  end

  it "denies quotes to technicians and hides other organizations' quotes" do
    quote = create_quote(scenario)

    sign_in_as(create(:membership, :technician, organization:))
    get quotes_path
    expect(response).to have_http_status(:forbidden)

    sign_in_as(create(:membership, :owner))
    get quote_path(quote)
    expect(response).to have_http_status(:not_found)
  end
end
