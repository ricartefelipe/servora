# frozen_string_literal: true

require "rails_helper"

RSpec.describe TimeEntries::Record do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:work_order) { open_work_order(scenario) }
  let(:technician) { create_technician(organization, name: "Diego") }

  it "stores minutes and the labor cost with the hourly cost in force" do
    entry = in_tenant(organization) do
      described_class.new(work_order:, membership: technician, started_at: tuesday_at(9), ended_at: tuesday_at(10, 30)).call
    end
    in_tenant(organization) { technician.update!(hourly_cost: BigDecimal("200")) }

    expect(in_tenant(organization) { entry.reload }).to have_attributes(minutes: 90, hourly_cost: BigDecimal("60"),
      labor_cost: BigDecimal("90.00"))
  end

  it "is idempotent with a client operation id" do
    operation = SecureRandom.uuid
    first, second = Array.new(2) do
      in_tenant(organization) do
        described_class.new(work_order:, membership: technician, started_at: tuesday_at(9), ended_at: tuesday_at(10),
          client_operation_id: operation, source: "offline").call
      end
    end

    expect(second.id).to eq(first.id)
    expect(in_tenant(organization) { TimeEntry.count }).to eq(1)
  end

  it "rejects inverted periods and finished orders" do
    expect do
      in_tenant(organization) do
        described_class.new(work_order:, membership: technician, started_at: tuesday_at(10), ended_at: tuesday_at(9)).call
      end
    end.to raise_error(described_class::InvalidEntry, /posterior/)
  end
end
