# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrderPolicy do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let!(:assigned) { open_work_order(scenario) }
  let!(:unassigned) { open_work_order(scenario, title: "Outra") }

  before { in_tenant(organization) { WorkOrders::Assign.new(work_order: assigned, membership: scenario[:technician]).call } }

  def context(membership) = PolicyContext.new(user: membership.user, membership:)

  def load(work_order) = in_tenant(organization) { WorkOrder.includes(:assignments).find(work_order.id) }

  it "limits technicians to their assigned work orders and equipment" do
    tech = context(scenario[:technician])

    orders = in_tenant(organization) { described_class::Scope.new(tech, WorkOrder.all).resolve.to_a }
    equipment = in_tenant(organization) { EquipmentPolicy::Scope.new(tech, Equipment.all).resolve.to_a }

    expect(orders).to eq([assigned])
    expect(equipment).to eq([scenario[:equipment]])
    expect(described_class.new(tech, load(unassigned)).show?).to be(false)
  end

  it "lets technicians execute but not formally complete, cancel or see prices" do
    policy = described_class.new(context(scenario[:technician]), load(assigned))

    expect(policy.update_execution?).to be(true)
    expect(policy.complete?).to be(false)
    expect(policy.cancel?).to be(false)
    expect(policy.view_prices?).to be(false)
  end

  it "gives office roles completion and authorization of additional items" do
    policy = described_class.new(context(scenario[:coordinator]), load(assigned))

    expect(policy.complete?).to be(true)
    expect(policy.decide_item?).to be(true)
    expect(policy.reopen?).to be(false)
    expect(described_class.new(context(create(:membership, :attendant, organization:)), load(assigned)).decide_item?).to be(false)
  end
end
