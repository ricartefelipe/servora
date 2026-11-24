# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preventive do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:contract) { create_contract(scenario) }
  let(:plan) { create_plan(scenario, contract) }

  it "generates month-end occurrences with their work orders and catches up after downtime" do
    generate_occurrences(plan, Date.new(2026, 4, 30))

    expect(occurrence_dates(plan)).to eq([[1, "2026-01-31"], [2, "2026-02-28"], [3, "2026-03-31"], [4, "2026-04-30"]])
    work_order = in_tenant(organization) { MaintenanceOccurrence.find_by!(sequence: 2).work_order }
    expect(work_order).to have_attributes(origin: "preventive", contract_id: contract.id, status: "approved",
      title: "Preventiva split — preventiva nº 2")
    expect(in_tenant(organization) { work_order.equipment.to_a }).to eq([scenario[:equipment]])
  end

  it "never duplicates occurrences when generation runs again" do
    2.times { generate_occurrences(plan, Date.new(2026, 2, 28)) }

    expect(occurrence_dates(plan).map(&:first)).to eq([1, 2])
    expect(in_tenant(organization) { WorkOrder.where(origin: "preventive").count }).to eq(2)
  end

  it "bounds each catch-up run" do
    yearly_backlog = create_plan(scenario, contract, title: "Semanal", frequency_unit: "week", anchor_date: Date.new(2026, 1, 1))

    generate_occurrences(yearly_backlog, Date.new(2026, 12, 31))
    expect(occurrence_dates(yearly_backlog).size).to eq(Preventive::GenerateOccurrences::MAX_PER_RUN)
    generate_occurrences(yearly_backlog, Date.new(2026, 12, 31))
    expect(occurrence_dates(yearly_backlog).map(&:first)).to eq((1..24).to_a)
  end

  it "re-anchors schedule changes without touching generated occurrences" do
    generate_occurrences(plan, Date.new(2026, 2, 28))
    original = in_tenant(organization) { WorkOrder.where(origin: "preventive").order(:created_at).pluck(:id, :title) }

    as_member(scenario[:coordinator]) do
      Preventive::SavePlan.new(contract:, plan: plan.reload, actor: scenario[:coordinator],
        attributes: { frequency_unit: "week", frequency_interval: 2, anchor_date: Date.new(2026, 3, 2) }).call
    end
    generate_occurrences(plan, Date.new(2026, 3, 16))

    expect(occurrence_dates(plan)).to eq([[1, "2026-01-31"], [2, "2026-02-28"], [3, "2026-03-02"], [4, "2026-03-16"]])
    expect(in_tenant(organization) { WorkOrder.where(id: original.map(&:first)).order(:created_at).pluck(:id, :title) })
      .to eq(original)
  end

  it "rejects a new anchor that does not move forward" do
    generate_occurrences(plan, Date.new(2026, 2, 28))

    expect do
      as_member(scenario[:coordinator]) do
        Preventive::SavePlan.new(contract:, plan: plan.reload, actor: nil, attributes: { anchor_date: Date.new(2026, 2, 1) }).call
      end
    end.to raise_error(Contracts::Errors::Invalid, /posterior à última ocorrência/)
  end

  it "schedules the next occurrence from the actual completion in after-completion mode" do
    plan = create_plan(scenario, contract, schedule_mode: "after_completion", anchor_date: Date.new(2026, 3, 1), lead_days: 5)

    generate_occurrences(plan, Date.new(2026, 3, 1))
    generate_occurrences(plan, Date.new(2026, 6, 1))
    expect(occurrence_dates(plan)).to eq([[1, "2026-03-01"]])

    first = in_tenant(organization) { MaintenanceOccurrence.sole.work_order }
    travel_to(Time.zone.local(2026, 3, 20, 15)) do
      ready_to_complete!(scenario, first)
      as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: first.reload, actor: scenario[:coordinator]).call }
    end
    generate_occurrences(plan, Date.new(2026, 4, 14))
    expect(occurrence_dates(plan).size).to eq(1)
    generate_occurrences(plan, Date.new(2026, 4, 15))

    expect(occurrence_dates(plan)).to eq([[1, "2026-03-01"], [2, "2026-04-20"]])
  end

  it "stops at the contract end, skips suspended periods and ignores inactive contracts" do
    as_member(scenario[:coordinator]) do
      Contracts::Save.new(organization:, contract:, actor: nil, attributes: { ends_on: Date.new(2026, 3, 15) },
        reason: "Prazo").call
    end
    generate_occurrences(plan, Date.new(2026, 12, 31))
    expect(occurrence_dates(plan).map(&:last)).to eq(%w[2026-01-31 2026-02-28])

    other = create_plan(scenario, contract, title: "Outro", anchor_date: Date.new(2026, 1, 10))
    as_member(scenario[:coordinator]) { Contracts::ChangeStatus.new(contract:, to: "suspended", actor: nil, reason: "Pausa").call }
    expect(generate_occurrences(other, Date.new(2026, 1, 10))).to eq([])
    as_member(scenario[:coordinator]) do
      Contracts::ChangeStatus.new(contract:, to: "active", actor: nil, today: Date.new(2026, 3, 1)).call
    end
    generate_occurrences(other, Date.new(2026, 3, 10))
    expect(occurrence_dates(other)).to eq([[3, "2026-03-10"]])
  end

  it "generates through the daily job for every active organization" do
    plan

    travel_to(Time.zone.local(2026, 2, 1, 1, 30)) { Preventive::GenerateDueJob.perform_now }

    expect(occurrence_dates(plan).map(&:first)).to eq([1])
  end
end
