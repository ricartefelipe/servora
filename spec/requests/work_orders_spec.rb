# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Work orders" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  it "opens a work order from the form" do
    sign_in_as(scenario[:coordinator])

    post work_orders_path, params: { work_order: { service_location_id: scenario[:location].id, title: "Vazamento",
                                                   problem_description: "Água pingando", origin: "whatsapp", priority: "urgent",
                                                   service_type_id: scenario[:service_type].id,
                                                   equipment_ids: [scenario[:equipment].id] } }

    work_order = in_tenant(organization) { WorkOrder.sole }
    expect(response).to redirect_to(work_order_path(work_order))
    follow_redirect!
    expect(response.body).to include("Vazamento", "Urgente", "Medir pressão de sucção")
  end

  it "completes a work order with assigned technicians and records them in the report" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call }
    ready_to_complete!(scenario, work_order)
    sign_in_as(scenario[:coordinator])

    post complete_work_order_path(work_order)

    report = in_tenant(organization) { WorkOrderReport.sole }
    expect(report.data["technicians"]).to eq([scenario[:technician].user.name])
  end

  it "shows why completion is refused" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])

    post complete_work_order_path(work_order)
    follow_redirect!

    expect(response.body).to include("Para concluir", "Registrar o diagnóstico")
  end

  it "lets the assigned technician fill the checklist and the technical report" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call }
    item = in_tenant(organization) { work_order.checklist_items.find_by!(response_kind: "check") }
    sign_in_as(scenario[:technician])

    patch work_order_checklist_item_path(work_order, item),
      params: { answer: { response: "sim", lock_version: item.lock_version } }
    patch update_report_work_order_path(work_order), params: { report: { diagnosis: "Filtro sujo", solution: "Limpeza",
                                                                         lock_version: 1 } }

    in_tenant(organization) do
      expect(item.reload.response).to eq("sim")
      expect(work_order.reload.diagnosis).to eq("Filtro sujo")
    end
    post complete_work_order_path(work_order)
    expect(response).to have_http_status(:forbidden)
  end

  it "hides unassigned work orders from technicians" do
    work_order = open_work_order(scenario)
    sign_in_as(scenario[:technician])

    get work_orders_path
    expect(response.body).not_to include(work_order.number)
    get work_order_path(work_order)
    expect(response).to have_http_status(:not_found)
  end

  it "converts an approved quote idempotently through the endpoint" do
    quote_scenario = build_quote_scenario(organization:)
    quote = create_quote(quote_scenario)
    version = send_quote(quote_scenario, quote)
    in_tenant(organization) do
      Quotes::Decide.new(quote: quote.reload, version_id: version.id, decision: "approved", digest: version.content_digest,
        contact: quote_scenario[:approver], channel: "portal").call
    end
    sign_in_as(scenario[:coordinator])

    2.times { post convert_quote_path(quote) }

    expect(in_tenant(organization) { WorkOrder.where(quote_version_id: version.id).count }).to eq(1)
    expect(flash[:notice]).to eq("Este orçamento já foi convertido.")
  end

  it "manages service types with checklist" do
    sign_in_as(scenario[:coordinator])

    post service_types_path, params: { service_type: { name: "Instalação", active: "1",
                                                       checklist_items_attributes: { "0" => { label: "Teste de estanqueidade",
                                                                                              response_kind: "check",
                                                                                              required: "1", position: "1" } } } }

    expect(in_tenant(organization) { ServiceType.find_by!(name: "Instalação").checklist_items.map(&:label) })
      .to eq(["Teste de estanqueidade"])
  end
end
