# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer portal service area" do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:contact) { create(:customer_contact, customer: scenario[:customer], portal_enabled: true, name: "Paula Reis") }

  it "opens a request for triage and notifies the office" do
    enter_portal(contact)

    post portal_work_orders_path, params: { request: { title: "Câmara fria acima de 10 °C", description: "Desde a madrugada.",
                                                       service_location_id: scenario[:location].id,
                                                       equipment_id: scenario[:equipment].id, urgency: "high" } }

    work_order = in_tenant(organization) { WorkOrder.find_by!(origin: "portal") }
    expect(work_order).to have_attributes(status: "open", priority: "high", requested_by_contact_id: contact.id,
      created_by_membership_id: nil)
    expect(in_tenant(organization) { work_order.equipment.to_a }).to eq([scenario[:equipment]])
    run_dispatcher
    expect(in_tenant(organization) { Notification.where(kind: "work_order.requested").pluck(:recipient_membership_id) })
      .to include(scenario[:coordinator].id)
    follow_redirect!
    expect(response.body).to include("Em análise", "Câmara fria acima de 10 °C")
  end

  it "refuses locations and equipment of other customers and empty requests" do
    foreign = create(:service_location, customer: create(:customer, organization:))
    enter_portal(contact)

    post portal_work_orders_path, params: { request: { title: "Teste", description: "x", service_location_id: foreign.id } }
    expect(response).to have_http_status(:not_found)

    post portal_work_orders_path, params: { request: { title: "", description: "", service_location_id: scenario[:location].id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Descreva o pedido")
  end

  it "shows only the customer's own orders, equipment, visits and charges" do
    own = open_work_order(scenario, title: "Ordem do cliente")
    open_work_order(build_work_order_scenario(organization:), title: "Ordem de outro cliente")
    enter_portal(contact)

    get portal_work_orders_path
    expect(response.body).to include("Ordem do cliente")
    expect(response.body).not_to include("Ordem de outro cliente")
    get portal_equipment_path(scenario[:equipment])
    expect(response.body).to include("Ordem do cliente")
    get portal_visits_path
    expect(response).to have_http_status(:ok)
    get portal_work_order_path(open_work_order(build_work_order_scenario(organization:)))
    expect(response).to have_http_status(:not_found)
    get portal_work_order_path(own)
    expect(response).to have_http_status(:ok)
  end

  it "lists charges with the payment link of the active charge" do
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "320.00")
    receivable = issue_receivable(scenario, work_order, "320.00")
    as_member(scenario[:coordinator]) { Payments::RequestCharge.new(receivable:, actor: nil).call }
    in_tenant(organization) { PaymentCharge.sole.update!(status: "submitted", payment_url: "https://pagamentos.exemplo/c/1") }
    enter_portal(contact)

    get portal_receivables_path

    expect(response.body).to include(receivable.number, "R$ 320,00", "https://pagamentos.exemplo/c/1", "não é nota fiscal")
  end

  it "downloads execution reports and proposals of the customer" do
    work_order = open_work_order(scenario)
    ready_to_complete!(scenario, work_order)
    as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }
    report = in_tenant(organization) { WorkOrderReport.sole }
    enter_portal(contact)

    get portal_work_order_report_path(work_order, report)

    expect(response.headers["Content-Type"]).to eq("application/pdf")
    expect(pdf_text(response.body)).to include("Relatório de execução", work_order.number)
  end
end
