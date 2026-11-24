# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PDF documents" do
  it "renders the commercial proposal of a sent version from its snapshot" do
    scenario = build_quote_scenario
    quote = create_quote(scenario,
      items: [["Higienização de evaporadora", "2", "240.00"], ["Diagnóstico técnico", "1", "150.00"]])
    send_quote(scenario, quote)
    sign_in_as(scenario[:author])

    get pdf_quote_path(quote, version: 1)

    expect(response.headers["Content-Type"]).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("proposta-#{quote.number}-v1.pdf")
    text = pdf_text(response.body)
    expect(text).to include("Proposta comercial", quote.number, "Higienização de evaporadora", "R$ 630,00", "não é nota fiscal")
  end

  it "does not render draft versions" do
    scenario = build_quote_scenario
    quote = create_quote(scenario)
    sign_in_as(scenario[:author])

    get pdf_quote_path(quote, version: 1)

    expect(response).to have_http_status(:not_found)
  end

  it "renders each execution report version" do
    scenario = build_work_order_scenario
    work_order = open_work_order(scenario)
    ready_to_complete!(scenario, work_order)
    as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }
    report = in_tenant(scenario[:organization]) { WorkOrderReport.sole }
    sign_in_as(scenario[:coordinator])

    get work_order_report_path(work_order, report)

    text = pdf_text(response.body)
    expect(text).to include("Relatório de execução", work_order.number, "Filtro obstruído", "Limpeza e recarga", "Medir pressão")
  end
end
