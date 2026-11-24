# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogItemPolicy do
  let(:organization) { create(:organization) }

  def context_for(role)
    membership = create(:membership, role:, organization:)
    PolicyContext.new(user: membership.user, membership:)
  end

  it "permits the cost attribute only to roles that manage the catalog and see costs" do
    item = build(:catalog_item, organization:)

    expect(described_class.new(context_for("admin"), item).permitted_attributes).to include(:unit_cost)
    expect(described_class.new(context_for("coordinator"), item).permitted_attributes).not_to include(:unit_cost)
    expect(described_class.new(context_for("finance"), item).create?).to be(false)
  end

  it "hides the catalog from roles without catalog access" do
    create(:catalog_item, organization:)
    context = PolicyContext.new(user: build(:user), membership: build(:membership, role: "auditor", organization:))
    context_without = PolicyContext.new(user: build(:user), membership: nil)

    expect(in_tenant(organization) { described_class::Scope.new(context, CatalogItem.all).resolve.count }).to eq(1)
    expect(context_without.can?(:catalog_view)).to be(false)
    expect(context_without.technician?).to be(false)
  end
end
