# frozen_string_literal: true

require "rails_helper"
require_relative "demo_story_helpers"

# Loads every seed file twice with the demonstration activity enabled (the
# full six-week story) at 03:55 of a Wednesday, as the daily re-seeding of the
# public demonstration does, checks what the first visitors see and that the
# history would convince a careful reader (equipment histories, priorities
# and deadlines, quotes), then lets the day go on (Demo::AdvanceStoryJob) to
# 11:00, 16:00 and 23:55. Other instants (a weekend re-seeding among them) are
# covered by demo_activity_clock_spec.rb and the living story in detail by
# demo_living_story_spec.rb, both with a shorter history.
RSpec.describe "Demonstration activity seed" do
  include DemoStoryHelpers

  let(:now) { local(2026, 12, 2, 3, 55) }
  let(:today) { now.to_date }

  before do
    travel_to(now)
    enable_demo_activity
  end

  def counted_models
    [Customer, WorkOrder, WorkOrderTransition, Visit, Quote, QuoteVersion, Receivable, Payment, StockMovement,
     StockReservation, MaterialConsumption, TimeEntry, SlaClock, MaintenanceOccurrence, WorkOrderReport, OutboxEvent,
     Notification, AuditEvent]
  end

  def snapshot
    %w[a b].index_with { |key| in_tenant(organization_id(key)) { counted_models.to_h { |model| [model.name, model.count] } } }
  end

  def isolation
    ids_a = in_tenant(organization_id("a")) { WorkOrder.pluck(:id) }
    ids_b = in_tenant(organization_id("b")) { WorkOrder.pluck(:id) }
    { b_sees_a: in_tenant(organization_id("b")) { WorkOrder.where(id: ids_a).count },
      a_sees_b: in_tenant(organization_id("a")) { WorkOrder.where(id: ids_b).count }, orders_b: ids_b.size }
  end

  def business_day?(date) = date.on_weekday? && !Seeds::HOLIDAYS.key?(date.iso8601)
  def history_days = ((today - 45)...today).select { |date| business_day?(date) }.last(Seeds::StoryClock.history_days)

  # Visits of each business day before today (the whole team).
  def daily_visits = history_days.map { |date| Visit.where(scheduled_start: whole_day(date)).count }

  # Hours logged by each technician over the history, as a share of the
  # working hours (9 h a day).
  def utilisation
    range = whole_day(history_days.first).begin...whole_day(today).begin
    TimeEntry.where(started_at: range).joins(membership: :user).group("users.name").sum(:minutes)
      .transform_values { |minutes| (BigDecimal(minutes) / (history_days.size * 9 * 60)).round(2) }
  end

  # Share of the closed deadlines that were met (SLA report), in percent:
  # all of them, or those of one metric and priority.
  def sla_met_percent(metric: nil, priority: nil)
    closed = SlaClock.joins(:work_order).where(status: %w[met breached])
    closed = closed.where(metric:, work_orders: { priority: }) if metric
    (BigDecimal(closed.where(status: "met").count) * 100 / closed.count).round(1)
  end

  # [serial, service type, request date] of every order with equipment.
  def unit_orders
    WorkOrder.joins(:equipment, :service_type)
      .pluck("equipment.serial_number", "service_types.name", :requested_at)
      .map { |serial, type, at| [serial, type, in_zone(at).to_date] }
  end

  # Smallest number of days between two orders of `type` on one unit, by unit.
  def closest_orders(type)
    unit_orders.select { |_, name, _| name == type }.group_by(&:first).filter_map do |serial, rows|
      dates = rows.map(&:last).sort
      [serial, dates.each_cons(2).map { |first, second| (second - first).to_i }.min] if dates.size > 1
    end.to_h
  end

  # Units whose preventive visits are closer than their interval allows.
  def preventives_too_close
    closest_orders("Manutenção preventiva de split").reject do |serial, days|
      interval = Seeds::DemoActivity::ClimaNortePool::UNITS.dig(serial, 1)
      days >= Seeds::DemoActivity::RoutineBook.interval_days(interval) - Seeds::DemoActivity::RoutineBook::PREVENTIVE_SLACK
    end
  end

  # Orders of the same customer requested less than 30 minutes apart.
  def near_duplicates
    WorkOrder.order(:requested_at).pluck(:customer_id, :requested_at).group_by(&:first).values.sum do |rows|
      rows.map(&:last).each_cons(2).count { |first, second| second - first < 30.minutes }
    end
  end

  # Orders of each home over the story, beyond one per unit plus one.
  def busy_homes
    Customer.where(kind: "individual").includes(:equipment).filter_map do |home|
      orders = WorkOrder.where(customer: home).count
      [home.name, orders] if orders > [home.equipment.size + 1, 3].min
    end
  end

  # Units each customer had when the story began (RoutineBook counts those).
  def registered_units
    [*Seeds::CUSTOMERS.fetch("a"), *Seeds::DemoActivity::ClimaNorte::CUSTOMERS,
     *Seeds::DemoActivity::ClimaNortePool::CUSTOMERS].to_h { |data| [data[:document], data[:equipment].size] }
  end

  # Businesses with more requests in some 30 days than RoutineBook allows:
  # their units plus COMPANY_EXTRA, plus QUIET_EXTRA on a quiet day of the
  # team (preventives and approved quotes are not requests).
  def busy_companies
    book = Seeds::DemoActivity::RoutineBook
    units = registered_units
    documents = Customer.where(kind: "company").to_h { |customer| [customer.id, customer.document] }
    WorkOrder.where(customer_id: documents.keys).where.not(origin: %w[preventive quote]).pluck(:customer_id, :requested_at)
      .group_by(&:first).filter_map do |customer_id, rows|
        most = busiest_window(rows.map { |_, at| in_zone(at).to_date }, book::COMPANY_WINDOW)
        document = documents.fetch(customer_id)
        [document, most] if most > units.fetch(document) + book::COMPANY_EXTRA + book::QUIET_EXTRA
      end
  end

  # Most dates that fall in one window of `days` consecutive days.
  def busiest_window(dates, days)
    dates.map { |date| dates.count { |other| other >= date && other - date < days } }.max
  end

  # Patrícia's relocation quote comes after the assessment visit it is based on.
  def relocation_assessed?
    quote = Quote.find_by!(title: "Remanejamento do split do quarto")
    assessment = WorkOrder.find_by!(customer_id: quote.customer_id, title: "Avaliação para remanejamento do split")
    assessment.status == "completed" && assessment.completed_at < quote.created_at
  end

  def corrective_orders = WorkOrder.joins(:service_type).where(service_types: { name: "Atendimento corretivo" })
  def preventive_orders = WorkOrder.joins(:service_type).where(service_types: { name: "Manutenção preventiva de split" })

  def priorities
    { high_repairs: (BigDecimal(corrective_orders.where(priority: "high").count) / corrective_orders.count).round(2),
      preventives: preventive_orders.distinct.pluck(:priority, :origin).sort,
      preventive_origins: preventive_orders.distinct.pluck(:origin) }
  end

  def quote_states
    Quote.includes(:current_version).to_h { |quote| [quote.title, [quote.status, quote.current_version.version_number]] }
  end

  # Orders linked to a contract that the contract does not cover, with the reason.
  def not_covered
    WorkOrder.where.not(contract_id: nil).includes(:contract).filter_map do |order|
      coverage = Contracts::Coverage.new(order).call
      [order.title, coverage.reason] unless coverage.covered
    end
  end

  def triage_order
    order = WorkOrder.find_by!(status: "open")
    clock = SlaClock.find_by!(work_order: order, metric: "first_response")
    { origin: order.origin, priority: order.priority, requested: in_zone(order.requested_at).strftime("%H:%M"),
      clock: clock.status, due: in_zone(clock.due_at) }
  end

  def settlement_dates = Receivable.pluck(:due_on) + Payment.pluck(:paid_at).map { |at| in_zone(at).to_date }

  # Each must be empty: ledgers, records after `instant`, equipment out of
  # operation without an open order, SLA notices and portal links out of order.
  def inconsistencies(instant)
    [inconsistent_ledgers, recorded_after(instant), unexplained_equipment, sla_notices_out_of_order,
     portal_links_after_sending]
  end

  def below_minimum = StockBalance.below_minimum.joins(:catalog_item, :warehouse).pluck("warehouses.name", "catalog_items.sku")
  def receipts_today = Payment.where(paid_at: whole_day(today)).sum(:amount)

  # Equipment out of operation without an open order that explains it.
  def unexplained_equipment
    open_orders = WorkOrder.where.not(status: %w[completed canceled]).joins(:equipment).pluck("equipment.serial_number")
    Equipment.where.not(operational_status: "operational").pluck(:serial_number) - open_orders
  end

  # The day goes on from the current (story) instant until `hour`: the SLA
  # scan every 5 minutes, as scheduled by config/recurring.yml, then the
  # story's events up to that time.
  def advance_to(hour, minute = 0)
    target = local(2026, 12, 2, hour, minute)
    from = Time.current
    ((target - from) / 5.minutes).floor.times do |step|
      travel_to(from + ((step + 1) * 5.minutes)) { in_tenant(organization_id("a")) { Sla::Scan.new.call } }
    end
    travel_to(target)
    Seeds::DemoActivity.advance
  end

  # What the first visitors see on the screens of organization A.
  def dawn_screens
    { open: WorkOrder.where.not(status: "completed").group(:status).count, quotes: quote_states, triage: triage_order,
      not_covered:, today: agenda(today), overdue: Receivable.overdue.count, below_minimum: }
  end

  # The routine work behind the reports.
  def history_figures
    daily = daily_visits
    { daily:, average: BigDecimal(daily.sum) / daily.size,
      utilisation: utilisation.values_at("Diego Alves", "Eduarda Lima", "Fábio Souza"), settlements: settlement_dates }
  end

  # What a careful reader of the orders, the equipment histories and the
  # reports would check.
  def believability
    { repairs_apart: closest_orders("Atendimento corretivo").values.min, preventives_too_close:, near_duplicates:,
      busy_homes:, busy_companies:, relocation_assessed: relocation_assessed?, **priorities, customers: Customer.count,
      quotes: Quote.count, quote_states: Quote.distinct.pluck(:status).sort,
      sla_high: sla_met_percent(metric: "resolution", priority: "high"),
      sla_normal: sla_met_percent(metric: "resolution", priority: "normal"), sla_met: sla_met_percent }
  end

  def consistency(instant)
    { problems: inconsistencies(instant), first_movement: StockMovement.minimum(:occurred_at),
      first_notification: Notification.minimum(:created_at) }
  end

  def mid_morning(applied)
    portal = WorkOrder.find_by!(title: "Split do quarto parado — residência")
    triage = SlaClock.find_by!(work_order: portal, metric: "first_response")
    { applied: applied.fetch("a").map { |_, action, key| [action, key] }, today: agenda(today), receipts: receipts_today,
      triage_breached: triage.breached_at.present?, below_minimum: }
  end

  # Renato's request, triaged as a corrective visit: checklist answered on
  # the visit and the bedroom split it names back in operation.
  def portal_outcome
    order = WorkOrder.find_by!(title: "Split do quarto parado — residência")
    [order.status, order.service_type.name, order.checklist_items.all? { |item| item.response.present? },
     order.equipment.pluck(:serial_number, :operational_status)]
  end

  def afternoon
    { again: Seeds::DemoActivity.advance, today: agenda(today), overdue: Receivable.overdue.count, portal: portal_outcome,
      waiting_parts: WorkOrder.where(status: "waiting_parts").count, below_minimum:, problems: inconsistencies(Time.current) }
  end

  # What a visitor sees late in the evening: the day's visits done and no
  # deadline overdue or at risk on the dashboard; the morning's first
  # response miss of Renato's request stays in the SLA report.
  def evening
    { today: agenda(today).values.flatten.uniq, deadlines_overdue: WorkOrder.deadline_overdue.count,
      deadlines_at_risk: WorkOrder.deadline_at_risk.count,
      missed_today: SlaClock.where(status: "breached", stopped_at: whole_day(today)).pluck(:metric),
      problems: inconsistencies(Time.current), equipment: unexplained_equipment }
  end

  it "records the story once, consistent and busy, and lets the day go on" do
    first = nil
    expect do
      load_seeds
      first = snapshot
      load_seeds
    end.to output(/Atividade de demonstração registrada.*Atividade de demonstração já existente/m).to_stdout
    again = [snapshot, isolation]

    in_tenant(organization_id("a")) do
      expect(dawn_screens.merge(again:)).to match(
        again: [first, { b_sees_a: 0, a_sees_b: 0, orders_b: 2 }],
        open: { "open" => 1, "approved" => 1, "scheduled" => 8, "waiting_parts" => 1 },
        quotes: include("Troca da placa eletrônica do split piso-teto" => ["draft", 1],
          "Higienização completa das evaporadoras da Loja Paulista" => ["sent", 2],
          "Troca do motor ventilador e do contator do split da sala de spinning" => ["approved", 1],
          "Higienização das evaporadoras dos consultórios" => ["converted", 1],
          "Substituição do split da sala de spinning" => ["rejected", 1],
          "Instalação de split na sala de treinamento" => ["expired", 1]),
        triage: { origin: "portal", priority: "high", clock: "running", requested: be > "17:00",
                  due: a_value_between(local(2026, 12, 2, 9, 0), local(2026, 12, 2, 11, 0)) },
        not_covered: [["Avaliação para instalação de split no depósito", "Tipo de serviço não coberto pelo contrato."]],
        today: { "Diego" => %w[scheduled scheduled], "Eduarda" => %w[scheduled scheduled], "Fábio" => %w[scheduled scheduled] },
        overdue: 1,
        below_minimum: contain_exactly(["Almoxarifado central", "PEC-FILTRO-14"], ["Almoxarifado central", "PEC-RELE-220"])
      )
      # Every business day up to yesterday has work for the team, with no day
      # crowded; settlements fall on business days.
      # No unit repaired twice within three weeks nor given two preventives in
      # one period, no home called too often, no request repeated minutes
      # later; about one repair in six is urgent, preventives never are; the
      # deadlines are missed at a believable rate per priority.
      expect(history_figures.merge(consistency(now), believability)).to match(
        daily: all(be_between(3, 9)), average: be_between(3.5, 6), utilisation: all(be_between(0.15, 0.45)),
        settlements: all(satisfy { |date| business_day?(date) }), problems: all(be_empty),
        first_movement: Seeds::StoryClock.origin(from: now), first_notification: be < now - 30.days,
        repairs_apart: be >= 21, preventives_too_close: be_empty, near_duplicates: 0, busy_homes: be_empty,
        busy_companies: be_empty, relocation_assessed: true,
        high_repairs: be_between(0.1, 0.25), preventives: all(satisfy { |priority, _| priority != "high" }),
        preventive_origins: ["preventive"],
        customers: be_between(20, 30), quotes: be_between(15, 25),
        quote_states: %w[approved converted draft expired rejected sent], sla_high: be_between(75, 85),
        sla_normal: be_between(93, 97), sla_met: be_between(92, 95.5)
      )
    end

    applied = advance_to(11)
    in_tenant(organization_id("a")) do
      expect(mid_morning(applied)).to match(
        applied: include(%i[pay c3], %i[start f1], %i[travel o1]), receipts: be >= BigDecimal("359.90"),
        triage_breached: true,
        today: { "Diego" => %w[completed traveling scheduled], "Eduarda" => %w[completed scheduled],
                 "Fábio" => %w[in_progress scheduled] },
        below_minimum: include(["Van 01 — Diego", "PEC-CAP-355"])
      )
    end

    advance_to(16)
    in_tenant(organization_id("a")) do
      expect(afternoon).to match(
        again: { "a" => [], "b" => [] }, overdue: 0, waiting_parts: 1, problems: all(be_empty),
        portal: ["completed", "Atendimento corretivo", true, [%w[E007412 operational]]],
        today: { "Diego" => %w[completed completed in_progress], "Eduarda" => %w[completed in_progress],
                 "Fábio" => %w[completed in_progress] },
        below_minimum: satisfy { |rows| rows.exclude?(["Almoxarifado central", "PEC-RELE-220"]) }
      )
    end

    advance_to(23, 55)
    in_tenant(organization_id("a")) do
      expect(evening).to match(today: ["completed"], deadlines_overdue: 0, deadlines_at_risk: 0,
        missed_today: ["first_response"],
        problems: all(be_empty), equipment: be_empty)
    end
  end
end
