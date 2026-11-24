# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractPolicy do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:contract) { create_contract(scenario) }

  def context(role) = PolicyContext.new(user: nil, membership: create(:membership, role, organization:))

  it "separates viewing, managing contracts and managing preventive plans" do
    matrix = %i[owner coordinator attendant technician finance auditor].to_h do |role|
      policy = described_class.new(context(role), contract)
      [role, [policy.show?, policy.update?, policy.add_plan?]]
    end

    expect(matrix).to eq(owner: [true, true, true], coordinator: [true, true, true], attendant: [true, false, false],
      technician: [false, false, false], finance: [true, false, false], auditor: [true, false, false])
  end

  it "freezes ended contracts and their plans" do
    plan = create_plan(scenario, contract)
    as_member(scenario[:coordinator]) do
      Contracts::ChangeStatus.new(contract:, to: "ended", actor: nil, reason: "Fim").call
    end
    owner = context(:owner)

    expect(described_class.new(owner, reload_in_tenant(contract)).update?).to be(false)
    expect(MaintenancePlanPolicy.new(owner, reload_in_tenant(plan)).generate?).to be(false)
  end
end
