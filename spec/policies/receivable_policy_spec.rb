# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceivablePolicy do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:receivable) do
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "300")
    issue_receivable(scenario, work_order, "300")
  end

  def context(role) = PolicyContext.new(user: nil, membership: create(:membership, role, organization:))

  it "grants each financial action only to the roles that hold its permission" do
    matrix = %i[owner admin coordinator attendant technician finance auditor].to_h do |role|
      policy = described_class.new(context(role), receivable)
      [role, [policy.show?, policy.register_payment?, policy.discount?, policy.refund?, policy.cancel?]]
    end

    expect(matrix).to eq(
      owner: [true, true, true, true, true], admin: [true, true, true, true, true],
      coordinator: [false, false, false, false, false], attendant: [false, false, false, false, false],
      technician: [false, false, false, false, false], finance: [true, true, true, true, true],
      auditor: [true, false, false, false, false]
    )
  end

  it "blocks actions on settled or canceled receivables" do
    pay(receivable, "300")
    policy = described_class.new(context(:finance), reload_in_tenant(receivable))

    expect([policy.register_payment?, policy.discount?, policy.cancel?, policy.charge?, policy.refund?])
      .to eq([false, false, false, false, true])
  end

  it "scopes receivables to financial roles" do
    receivable
    resolve = ->(role) { in_tenant(organization) { described_class::Scope.new(context(role), Receivable.all).resolve.count } }

    expect([resolve.call(:finance), resolve.call(:coordinator)]).to eq([1, 0])
  end
end
