# frozen_string_literal: true

require "rails_helper"

# Two schedulers (e.g. a retried job and the next run) generate the same plan
# at the same time. The plan row lock serializes them; the second one re-reads
# last_sequence and finds nothing left to generate.
RSpec.describe Preventive, :committed do # concurrent generation
  it "generates each occurrence exactly once" do
    scenario = build_work_order_scenario
    plan = create_plan(scenario, create_contract(scenario))

    counts = ConcurrencyHelpers.run_in_parallel(3) { generate_occurrences(plan, Date.new(2026, 3, 31)).size }

    expect(counts.sum).to eq(3)
    expect(occurrence_dates(plan).map(&:first)).to eq([1, 2, 3])
    expect(in_tenant(plan.organization_id) { WorkOrder.where(origin: "preventive").count }).to eq(3)
  end
end
