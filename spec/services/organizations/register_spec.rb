# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::Register do
  let(:user) { create(:user) }

  it "creates the organization with the user as owner and audits it" do
    result = described_class.new(user:, attributes: { name: "Clima Leste", segment: "hvac", time_zone: "America/Sao_Paulo" }).call

    in_tenant(result.organization) do
      expect(result.membership.reload).to have_attributes(role: "owner", user_id: user.id, status: "active")
      expect(AuditEvent.last).to have_attributes(action: "organization.created", actor_user_id: user.id)
    end
  end

  it "rolls back everything when the organization is invalid" do
    expect { described_class.new(user:, attributes: { name: "" }).call }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Servora::Tenancy.with_context(user_id: user.id) { Membership.count }).to eq(0)
  end
end
