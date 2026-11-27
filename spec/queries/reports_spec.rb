# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }
  let(:period) { Reports::Period.parse(from: "2026-11-01", to: "2026-11-30", today: Date.new(2026, 11, 24)) }

  def report(klass, show_costs: true) = klass.new(period:, zone:, show_costs:)
  def at(text) = zone.parse(text)

  def completed_order(title:, unit_price:, unit_cost:, logged: nil)
    order = travel_to(at("2026-11-10 09:00")) { open_work_order(scenario, title:) }
    add_authorized_item(scenario, order, unit_price:, unit_cost:)
    in_tenant(organization) { WorkOrders::Assign.new(work_order: order, membership: scenario[:technician]).call }
    log_time(order, *logged) if logged
    complete(order)
  end

  def complete(order)
    ready_to_complete!(scenario, order)
    travel_to(at("2026-11-12 15:00")) do
      as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: order.reload, actor: scenario[:coordinator]).call }
    end
    order
  end

  it "summarizes work orders opened and completed in the period with the average lead time" do
    completed_order(title: "Split da recepção", unit_price: "500", unit_cost: "200")
    travel_to(at("2026-10-20 09:00")) { open_work_order(scenario, title: "Fora do período") }

    summary = in_tenant(organization) { report(Reports::WorkOrdersReport).summary }
    rows = in_tenant(organization) { report(Reports::WorkOrdersReport).rows(limit: 10) }

    expect(summary).to include("Abertas no período" => 1, "Concluídas no período" => 1, "Tempo médio até a conclusão (h)" => 54)
    expect(rows.map(&:second)).to eq(["Split da recepção"])
  end

  def log_time(order, from, to)
    in_tenant(organization) do
      TimeEntries::Record.new(work_order: order, membership: scenario[:technician], started_at: at(from), ended_at: at(to)).call
    end
  end

  it "shows productivity per technician and hides labor cost without the cost permission" do
    completed_order(title: "Preventiva", unit_price: "300", unit_cost: "100", logged: ["2026-11-11 08:00", "2026-11-11 10:30"])

    with_costs = in_tenant(organization) { report(Reports::ProductivityReport).rows(limit: 10) }
    without_costs = in_tenant(organization) { report(Reports::ProductivityReport, show_costs: false) }

    expect(with_costs.first[0..3]).to eq([scenario[:technician].user.name, 1, 0, BigDecimal("2.5")])
    expect(without_costs.headers).not_to include("Custo de mão de obra")
  end

  it "reports billing, receipts and realized margin of completed work orders" do
    order = completed_order(title: "Manutenção", unit_price: "1000", unit_cost: "400")
    receivable = travel_to(at("2026-11-13 10:00")) { issue_receivable(scenario, order, "1000", due_on: Date.new(2026, 11, 20)) }
    travel_to(at("2026-11-14 10:00")) { pay(receivable, "600") }

    summary = travel_to(at("2026-11-24 10:00")) { in_tenant(organization) { report(Reports::FinanceReport).summary } }

    expect(summary.transform_values { |value| value.is_a?(Reports::Money) ? value.value : value }).to include(
      "Faturado no período" => 1000, "Recebido no período" => 600, "Saldo em aberto hoje" => 400, "Vencido hoje" => 400,
      "Receita das ordens concluídas" => 1000, "Margem realizada" => 1000
    )
  end

  it "aggregates material consumption net of returns at historical cost" do
    order = travel_to(at("2026-11-05 09:00")) { open_work_order(scenario) }
    warehouse = create(:warehouse, organization:)
    item = stock_part(organization, name: "Capacitor")
    receive_stock(warehouse, item, "10", "20")
    consumption = travel_to(at("2026-11-06 10:00")) do
      as_member(scenario[:coordinator]) { Inventory::Consume.new(work_order: order, warehouse:, item:, quantity: "3", actor: nil).call }
    end
    in_tenant(organization) { Inventory::ReturnConsumption.new(consumption:, quantity: "1", actor: nil).call }

    rows = in_tenant(organization) { report(Reports::MaterialsReport).rows(limit: 10) }

    expect(rows).to eq([["Capacitor", "un", BigDecimal("2"), Reports::Money.of("40")]])
  end

  it "counts met and breached deadlines closed in the period" do
    configure_sla(organization)
    order = travel_to(at("2026-11-17 09:00")) { open_work_order(scenario) }
    travel_to(at("2026-11-17 10:00")) { move(scenario, order, "in_progress") }

    summary = in_tenant(organization) { report(Reports::SlaReport).summary }

    expect(summary).to include("Prazos encerrados" => 1, "Cumpridos" => 1,
      "Percentual cumprido" => Reports::Percent.new(value: BigDecimal("100.0")))
  end

  it "lists deadlines from the most to the least severe priority" do
    configure_sla(organization)
    in_tenant(organization) do
      %w[urgent normal low].each do |priority|
        SlaPolicy.create!(organization:, priority:, first_response_minutes: 120, resolution_minutes: 480,
          business_hours_only: true, warning_percent: 80)
      end
    end
    orders = %w[low urgent normal high].map do |priority|
      travel_to(at("2026-11-17 09:00")) { open_work_order(scenario, title: priority, priority:) }
    end
    orders.each { |order| travel_to(at("2026-11-17 10:00")) { move(scenario, order, "in_progress") } }

    rows = in_tenant(organization) { report(Reports::SlaReport).rows(limit: 10) }

    expect(rows.map { |row| row.first(2) }).to eq([["Primeira resposta", "Urgente"], ["Primeira resposta", "Alta"],
                                                   ["Primeira resposta", "Normal"], ["Primeira resposta", "Baixa"]])
  end
end
