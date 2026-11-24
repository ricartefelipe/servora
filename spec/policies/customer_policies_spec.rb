# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer and equipment policies" do
  let(:organization) { create(:organization) }

  def context_for(role)
    membership = create(:membership, role:, organization:)
    PolicyContext.new(user: membership.user, membership:)
  end

  it "lets attendants manage customers and equipment but not technicians" do
    customer = build(:customer, organization:)

    expect(CustomerPolicy.new(context_for("attendant"), customer).create?).to be(true)
    expect(CustomerPolicy.new(context_for("technician"), customer).show?).to be(false)
    expect(CustomerPolicy.new(context_for("finance"), customer).update?).to be(false)
    expect(CustomerPolicy.new(context_for("finance"), customer).show?).to be(true)
  end

  it "blocks edits of archived records until they are restored" do
    archived = build(:customer, organization:, archived_at: Time.current)
    policy = CustomerPolicy.new(context_for("admin"), archived)

    expect(policy.update?).to be(false)
    expect(policy.restore?).to be(true)
  end

  it "does not expose the asset base to technicians before assignments exist" do
    create(:equipment, location: create(:service_location, customer: create(:customer, organization:)))
    context = context_for("technician")

    resolved = in_tenant(organization) { EquipmentPolicy::Scope.new(context, Equipment.all).resolve.to_a }

    expect(resolved).to be_empty
  end
end
