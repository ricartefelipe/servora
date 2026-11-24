# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Identity policies" do
  let(:organization) { create(:organization) }

  def context_for(role)
    membership = create(:membership, role:, organization:)
    PolicyContext.new(user: membership.user, membership:)
  end

  describe MembershipPolicy do
    let(:owner_context) { context_for("owner") }
    let(:admin_context) { context_for("admin") }
    let(:technician_context) { context_for("technician") }
    let(:other_owner) { create(:membership, :owner, organization:) }
    let(:coordinator) { create(:membership, :coordinator, organization:) }

    it "lets admins manage non-owner members only" do
      expect(described_class.new(admin_context, coordinator).update?).to be(true)
      expect(described_class.new(admin_context, other_owner).update?).to be(false)
      expect(described_class.new(owner_context, other_owner).update?).to be(true)
    end

    it "never lets a member change their own access" do
      expect(described_class.new(owner_context, owner_context.membership).update?).to be(false)
    end

    it "denies team management to technicians" do
      expect(described_class.new(technician_context, coordinator).update?).to be(false)
      expect(described_class.new(technician_context, coordinator).index?).to be(false)
    end

    it "only offers the owner role to owners" do
      expect(described_class.new(admin_context, coordinator).assignable_roles).not_to include("owner")
      expect(described_class.new(owner_context, coordinator).assignable_roles).to include("owner")
    end

    it "permits the hourly cost only to roles that see costs" do
      expect(described_class.new(owner_context, coordinator).permitted_attributes).to include(:hourly_cost)
      expect(described_class.new(context_for("coordinator"), coordinator).permitted_attributes).not_to include(:hourly_cost)
    end

    it "scopes technicians to their own membership" do
      coordinator
      scope = in_tenant(organization) { described_class::Scope.new(technician_context, Membership.all).resolve.to_a }

      expect(scope).to eq([technician_context.membership])
    end
  end

  describe InvitationPolicy do
    it "lets only owners invite new owners" do
      owner_invite = build(:invitation, organization:, role: "owner")

      expect(described_class.new(context_for("admin"), owner_invite).create?).to be(false)
      expect(described_class.new(context_for("owner"), owner_invite).create?).to be(true)
      expect(described_class.new(context_for("attendant"), build(:invitation, organization:)).create?).to be(false)
    end
  end

  describe AuditEventPolicy do
    it "is visible to owners, admins and auditors" do
      expect(described_class.new(context_for("auditor"), AuditEvent).index?).to be(true)
      expect(described_class.new(context_for("finance"), AuditEvent).index?).to be(false)
    end
  end

  describe OrganizationPolicy do
    it "restricts settings to the member's own organization" do
      context = context_for("admin")

      expect(described_class.new(context, organization).update?).to be(true)
      expect(described_class.new(context, build(:organization)).update?).to be(false)
      expect(described_class.new(context_for("coordinator"), organization).update?).to be(false)
    end
  end
end
