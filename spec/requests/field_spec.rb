# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Field area" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:technician) { scenario[:technician] }
  let!(:work_order) { open_work_order(scenario, title: "Câmara fria sem refrigerar") }

  before { in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: technician).call } }

  def operation(kind, payload, version: nil, order: work_order)
    body = { operation: { id: SecureRandom.uuid, kind:, version:, work_order_id: order.id, payload: } }
    post field_operations_path, params: body, as: :json
  end

  it "lists the technician's visits and assigned orders" do
    sign_in_as(technician)

    get field_root_path

    expect(response.body).to include("Minha agenda", "Câmara fria sem refrigerar", "Atribuídas sem visita marcada")
  end

  it "shows the mobile execution view with offline-capable forms" do
    sign_in_as(technician)

    get field_work_order_path(work_order)

    expect(response.body).to include("Checklist", "Registro técnico", "Apontar horas", 'data-controller="field-sync"',
      'data-kind="technical_report"')
  end

  it "applies operations as JSON and revalidates access on every request" do
    sign_in_as(technician)

    operation("technical_report", { diagnosis: "Compressor travado", solution: "Substituição" })
    expect(response.parsed_body).to include("status" => "applied")

    other_order = open_work_order(scenario, title: "Não atribuída")
    operation("technical_report", { diagnosis: "x" }, order: other_order)
    expect(response).to have_http_status(:not_found)

    as_member(scenario[:coordinator]) { WorkOrders::Cancel.new(work_order:, actor: scenario[:coordinator], reason: "Duplicada").call }
    operation("technical_report", { diagnosis: "depois" })
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses malformed operations" do
    sign_in_as(technician)

    body = { operation: { id: "não-é-uuid", kind: "checklist", work_order_id: work_order.id, payload: { a: 1 } } }
    post field_operations_path, params: body, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "keeps the field area to members who execute work orders" do
    sign_in_as(scenario[:coordinator])

    get field_root_path

    expect(response).to have_http_status(:forbidden)
  end

  it "serves a service worker that caches only static assets" do
    get pwa_service_worker_path(format: :js)

    expect(response.body).to include('url.pathname.startsWith("/assets/")', "/offline.html")
    expect(response.body).to include("fetch(request).catch(() => caches.match(OFFLINE_PAGE))")
  end
end
