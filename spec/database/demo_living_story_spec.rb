# frozen_string_literal: true

require "rails_helper"
require_relative "demo_story_helpers"

# The public demonstration is re-seeded at 03:55; Demo::AdvanceStoryJob then
# applies today's events as their time comes (Seeds::DemoActivity::Living).
# The routine history is left out (no technician in HistoryPlan) to keep each
# load cheap: today's events are all hand-written. The full story is covered
# by demo_activity_seed_spec.rb.
RSpec.describe "Living demonstration story" do
  include DemoStoryHelpers

  let(:day) { Date.new(2026, 12, 2) }
  let(:nothing) { { "a" => [], "b" => [] } }

  before do
    allow(Seeds::StoryClock).to receive(:history_days).and_return(6)
    stub_const("Seeds::DemoActivity::HistoryPlan::TECHNICIANS", [])
    enable_demo_activity
    travel_to(local(2026, 12, 2, 3, 55))
    quietly { load_seeds }
  end

  def advance_to(hour, minute = 0)
    travel_to(local(2026, 12, 2, hour, minute))
    Seeds::DemoActivity.advance
  end

  def applied_keys(applied) = applied.fetch("a").map { |_, action, key| [action, key] }
  def visit_of(order) = Visit.where(work_order: order).order(:scheduled_start).last
  def order_titled(title) = WorkOrder.find_by!(title:)
  def receipts(date) = Payment.where(paid_at: whole_day(date)).sum(:amount)
  def restaurant = order_titled("Split do salão desarmando no horário de pico")
  def prisma = order_titled("Cassete da recepção desarmando o disjuntor")
  def clinic = order_titled("Split do consultório 2 pingando")
  def academy = order_titled("Preventiva geral dos splits antes do verão")
  def portal_request = order_titled("Split do quarto parado — residência")

  # The visitor's changes stay, and the story waits for them: Diego does not
  # leave for the Academy while the restaurant visit he started is under
  # way, and the clinic's order is not completed while an item waits for
  # the customer's authorization.
  def visitor_outcome
    in_tenant(organization_id("a")) do
      [restaurant.status, visit_of(restaurant).status, restaurant.receivables.count, visit_of(prisma).status,
       visit_of(academy).status, clinic.status, clinic.receivables.count]
    end
  end

  # Visit states of the day, orders completed today, deadlines overdue and
  # at risk (the dashboard's "prazo estourado" and "em risco") and the
  # agenda of the next business day, at 18:00 and at 23:55.
  def day_end
    [advance_to(18), advance_to(23, 55)].map do
      in_tenant(organization_id("a")) do
        [agenda(day).values.flatten.uniq, WorkOrder.where(completed_at: whole_day(day)).count,
         WorkOrder.deadline_overdue.count, WorkOrder.deadline_at_risk.count,
         WorkOrder.where(status: %w[waiting_parts waiting_customer]).pluck(:status), agenda(day + 1)]
      end
    end
  end

  # Renato's request after the triage and the visit: classified as a
  # corrective visit, its checklist answered, the bedroom split it names
  # back in operation.
  def portal_outcome
    in_tenant(organization_id("a")) do
      order = portal_request
      [order.service_type&.name, order.checklist_items.map { |item| item.response.present? }.uniq,
       order.equipment.pluck(:serial_number, :operational_status)]
    end
  end

  # The clinic's order waits for the customer and its next visit is called off, with the reason.
  def clinic_wait
    in_tenant(organization_id("a")) do
      order = order_titled("Revisão do split do consultório 1")
      [order.status, order.visits.pluck(:status, :cancel_reason)]
    end
  end

  def below_minimum = StockBalance.below_minimum.joins(:catalog_item).pluck("catalog_items.sku")
  def afternoon_state = [agenda(day + 1)["Eduarda"], WorkOrder.where(status: "waiting_parts").count, Receivable.overdue.count]

  def add_pending_item(work_order)
    WorkOrders::AddItem.new(work_order:, actor: member("bruno@clima-norte.test"), quantity: "1",
      catalog_item: CatalogItem.find_by!(sku: "PEC-CAP-355")).call
  end

  it "applies today's events as their time comes, each one once" do
    in_tenant(organization_id("a")) { expect([agenda(day).values.flatten.uniq, receipts(day)]).to eq([["scheduled"], 0]) }

    morning = advance_to(11)
    aggregate_failures "at 11:00" do
      expect(applied_keys(morning)).to include(%i[travel c3], %i[finish s1], %i[pay c3], %i[start f1])
      expect(morning.fetch("b").map { |_, action, _| action }).to eq(%i[travel start report finish complete])
      expect(advance_to(11)).to eq(nothing)
      in_tenant(organization_id("a")) do
        expect(agenda(day)).to eq("Diego" => %w[completed traveling scheduled], "Eduarda" => %w[completed scheduled],
          "Fábio" => %w[in_progress scheduled])
        expect([receipts(day), recorded_after(Time.current)]).to eq([BigDecimal("359.90"), {}])
      end
    end

    afternoon = advance_to(16)
    aggregate_failures "at 16:00" do
      expect(applied_keys(afternoon)).to include(%i[complete o1], %i[reserve w1], %i[pay c0], %i[start tv1],
        [:receive_stock, nil])
      expect(advance_to(16)).to eq(nothing)
      in_tenant(organization_id("a")) do
        expect(agenda(day)).to eq("Diego" => %w[completed completed in_progress], "Eduarda" => %w[completed in_progress],
          "Fábio" => %w[completed in_progress])
        expect(afternoon_state).to eq([%w[scheduled], 1, 0])
        expect(below_minimum).not_to include("PEC-RELE-220")
        expect([recorded_after(Time.current), inconsistent_ledgers]).to all(be_empty)
      end
    end

    expect(portal_outcome).to eq(["Atendimento corretivo", [true], [%w[E007412 operational]]])

    # The relay's return visit is scheduled at 17:40, the clinic's order
    # waits for the customer (its visit of the next business day canceled)
    # and the request that arrived at 14:10 is scheduled for that day: no
    # deadline runs out nor is at risk by the end of the day.
    expect(day_end).to all(eq([["completed"], 6, 0, 0, ["waiting_customer"],
                               { "Diego" => %w[canceled scheduled], "Eduarda" => %w[scheduled scheduled],
                                 "Fábio" => %w[scheduled scheduled] }]))
    expect(clinic_wait).to eq(["waiting_customer",
                               [["canceled", "Cancelada a pedido da clínica até a conclusão da reforma da recepção."]]])
  end

  # The story counts its days with the holidays the seed loaded: a holiday
  # added by a visitor (here, on the last business day) changes the SLA
  # deadlines from then on, but not the instants of the story.
  it "keeps its days when a visitor adds a holiday" do
    allow(Rails.logger).to receive(:warn).and_call_original
    in_tenant(organization_id("a")) do
      Holiday.create!(organization_id: organization_id("a"), date: day - 1, name: "Feriado municipal")
    end

    expect(applied_keys(advance_to(11))).to include(%i[pay c3], %i[start f1], %i[triage o1])
    expect(applied_keys(advance_to(17))).to include(%i[open_order n2], %i[wait_customer s2], %i[cancel_visit s2])
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including("demo.story_event_skipped"))
  end

  it "skips, without errors, the events of visits and orders that visitors changed" do
    allow(Rails.logger).to receive(:warn).and_call_original
    in_tenant(organization_id("a")) do
      travel_to(local(2026, 12, 2, 7, 10)) do
        Visits::Start.new(visit: visit_of(restaurant), actor: member("diego@clima-norte.test")).call
      end
      travel_to(local(2026, 12, 2, 8, 40)) do
        Visits::Cancel.new(visit: visit_of(prisma), actor: member("bruno@clima-norte.test"),
          reason: "Cliente pediu outro dia.").call
      end
    end
    advance_to(9, 10)
    in_tenant(organization_id("a")) { travel_to(local(2026, 12, 2, 9, 12)) { add_pending_item(clinic) } }

    applied = applied_keys(advance_to(16))
    keys = applied.map(&:last)
    portal = applied.filter_map { |action, key| action if key == :o1 }
    expect([keys & %i[c3 f1 ip1], keys & %i[s1 c0], portal, applied & [%i[complete s1], %i[bill s1]]])
      .to eq([[], %i[s1 c0], %i[triage schedule], []])
    expect(advance_to(16)).to eq(nothing)
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including("demo.story_event_skipped"))
    expect(visitor_outcome).to eq(["in_progress", "in_progress", 0, "canceled", "scheduled", "in_progress", 0])
  end

  it "does nothing on another day than the one the story was recorded on" do
    travel_to(local(2026, 12, 3, 0, 30))
    expect(Seeds::DemoActivity.advance).to eq(nothing)
    # A day without the re-seeding: the story of the day before is not replayed on it.
    travel_to(local(2026, 12, 3, 16, 0))
    expect(Seeds::DemoActivity.advance).to eq(nothing)
  end
end
