# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reports" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  it "lists the reports allowed to each role" do
    sign_in_as(scenario[:coordinator])
    get reports_path
    expect(response.body).to include("Ordens de serviço", "Produtividade por técnico", "Prazos (SLA)")
    expect(response.body).not_to include(">Financeiro<")

    sign_in_as(create(:membership, :finance, organization:))
    get reports_path(relatorio: "financeiro")
    expect(response.body).to include("Faturado no período", "Margem realizada")

    sign_in_as(scenario[:technician])
    get reports_path
    expect(response).to have_http_status(:forbidden)
  end

  it "exports CSV neutralizing spreadsheet formulas and records the export" do
    open_work_order(scenario, title: "=HYPERLINK(\"https://exemplo.invalid\")")
    sign_in_as(scenario[:coordinator])

    get export_report_path(relatorio: "ordens", de: Time.zone.today.beginning_of_month.iso8601, ate: Time.zone.today.iso8601)

    expect(response.headers["Content-Type"]).to start_with("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment", "servora-ordens-")
    body = response.body.force_encoding("UTF-8")
    expect(body).to start_with("﻿Número;Título")
    expect(body).to include("\"'=HYPERLINK(\"\"https://exemplo.invalid\"\")\"")
    expect(in_tenant(organization) { AuditEvent.where(action: "report.exported").count }).to eq(1)
  end

  it "refuses exports of reports outside the member's permissions or plan" do
    sign_in_as(scenario[:coordinator])
    get export_report_path(relatorio: "financeiro")
    expect(response).to have_http_status(:not_found)

    owner = create(:membership, :owner, organization:)
    in_tenant(organization) do
      plan = Plan.find_by!(code: "essencial")
      Subscription.create!(organization:, plan:, status: "active", technician_seats: 3, monthly_amount: plan.monthly_price,
        activated_at: Time.current)
    end
    sign_in_as(owner)
    get reports_path
    expect(response.body).not_to include("Consumo de materiais", ">Financeiro<")
  end

  it "shows deadline percentages in the pt-BR format and exports them as plain numbers" do
    zone = ActiveSupport::TimeZone[organization.time_zone]
    configure_sla(organization)
    on_time = travel_to(zone.parse("2026-11-17 09:00")) { open_work_order(scenario, title: "No prazo") }
    late = travel_to(zone.parse("2026-11-17 09:00")) { open_work_order(scenario, title: "Atrasada") }
    travel_to(zone.parse("2026-11-17 10:00")) { move(scenario, on_time, "in_progress") }
    travel_to(zone.parse("2026-11-17 16:00")) { move(scenario, late, "in_progress") }
    sign_in_as(scenario[:coordinator])

    period = { de: "2026-11-01", ate: "2026-11-30" }
    get reports_path(relatorio: "prazos", **period)

    page = response.parsed_body
    figures = page.css("section[aria-label='Indicadores do período'] > div").map { |cell| cell.text.squish }
    expect(figures).to include("Percentual cumprido 50,0%")
    expect(page.css("table.sv-table tbody td").map { |cell| cell.text.squish }).to include("50,0%")

    get export_report_path(relatorio: "prazos", **period)
    expect(response.body.force_encoding("UTF-8").lines.second.chomp).to end_with(";2;1;1;50.0")
  end

  it "only aggregates the organization's own data" do
    other = build_work_order_scenario
    open_work_order(other, title: "Ordem de outra organização")
    open_work_order(scenario, title: "Ordem própria")
    sign_in_as(scenario[:coordinator])

    get reports_path(relatorio: "ordens")

    expect(response.body).to include("Ordem própria")
    expect(response.body).not_to include("Ordem de outra organização")
  end
end
