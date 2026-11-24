# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }
  let(:technician) { create(:membership, :technician, organization:) }

  describe Memberships::Update do
    it "changes the role and audits the change" do
      as_member(owner) { described_class.new(membership: technician, attributes: { role: "coordinator" }).call }

      in_tenant(organization) do
        expect(technician.reload.role).to eq("coordinator")
        expect(AuditEvent.find_by(action: "membership.updated").changeset).to include("role" => %w[technician coordinator])
      end
    end

    it "never leaves the organization without an owner" do
      expect { as_member(owner) { described_class.new(membership: owner, attributes: { role: "admin" }).call } }
        .to raise_error(Memberships::OwnerGuard::LastOwner)
    end

    it "allows demoting an owner when another active owner remains" do
      create(:membership, :owner, organization:)

      as_member(owner) { described_class.new(membership: owner, attributes: { role: "admin" }).call }

      expect(in_tenant(organization) { owner.reload.role }).to eq("admin")
    end
  end

  describe Memberships::Deactivate do
    it "deactivates and records who did it" do
      as_member(owner) { described_class.new(membership: technician, actor: owner.user).call }

      expect(in_tenant(organization) { technician.reload })
        .to have_attributes(status: "deactivated", deactivated_by_user_id: owner.user_id)
    end

    it "protects the last owner" do
      expect { as_member(owner) { described_class.new(membership: owner, actor: owner.user).call } }
        .to raise_error(Memberships::OwnerGuard::LastOwner)
    end
  end

  describe Memberships::Reactivate do
    it "restores access" do
      in_tenant(organization) { technician.update!(status: "deactivated", deactivated_at: Time.current) }

      as_member(owner) { described_class.new(membership: technician).call }

      expect(in_tenant(organization) { technician.reload }).to have_attributes(status: "active", deactivated_at: nil)
    end
  end
end
