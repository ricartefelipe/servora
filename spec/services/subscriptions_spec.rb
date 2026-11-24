# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def subscribe(plan_code, status: "active", seats: nil, addons: [], trial_ends_on: nil)
    in_tenant(organization) do
      plan = Plan.find_by!(code: plan_code)
      Subscription.create!(organization:, plan:, status:, trial_ends_on:, technician_seats: seats || plan.included_technicians,
        addon_modules: addons, monthly_amount: plan.monthly_price)
    end
  end

  it "starts every new organization with a trial of the complete plan" do
    user = create(:user)
    result = Organizations::Register.new(user:, attributes: { name: "Refrigeração Aurora", segment: "hvac",
                                                              time_zone: "America/Sao_Paulo" }).call

    subscription = in_tenant(result.organization) { Subscription.sole }
    expect(subscription).to have_attributes(status: "trialing", trial_ends_on: Time.zone.today + 14, technician_seats: 30)
    expect(subscription.plan.code).to eq("empresarial")
    expect(in_tenant(result.organization) { subscription.module_enabled?(:finance) }).to be(true)
  end

  it "enables modules from the plan and paid add-ons" do
    subscription = subscribe("essencial", addons: %w[inventory])

    in_tenant(organization) do
      expect(%i[inventory preventive finance api].map do |code|
        subscription.module_enabled?(code)
      end).to eq([true, false, false, false])
    end
  end

  it "limits technicians to the contracted seats, counting pending invitations" do
    subscribe("essencial", seats: 2)
    create(:membership, :technician, organization:)
    as_member(owner) { Invitations::Issue.new(inviter: owner, email: "tecnico2@exemplo.test", role: "technician").call }

    expect do
      as_member(owner) { Invitations::Issue.new(inviter: owner, email: "tecnico3@exemplo.test", role: "technician").call }
    end.to raise_error(Servora::RuleViolation, /vagas de técnico/)
    expect do
      as_member(owner) { Invitations::Issue.new(inviter: owner, email: "atendente@exemplo.test", role: "attendant").call }
    end.not_to raise_error
  end

  it "prices changes and refuses fewer seats than technicians in use" do
    subscription = subscribe("profissional", status: "trialing", trial_ends_on: Time.zone.today + 3)
    create_list(:membership, 3, :technician, organization:)
    change = lambda do |seats, activate: false|
      as_member(owner) do
        described_class::Change.new(subscription: subscription.reload, plan_code: "profissional", seats:, addons: %w[finance api],
          actor: owner, activate:).call
      end
    end

    expect { change.call(2) }.to raise_error(Servora::RuleViolation, /3 técnicos ativos/)
    change.call(12, activate: true)

    expect(reload_in_tenant(subscription)).to have_attributes(status: "active", technician_seats: 12, trial_ends_on: nil,
      addon_modules: %w[finance api], monthly_amount: BigDecimal("1010.00"))
  end
end
