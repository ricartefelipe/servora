# frozen_string_literal: true

require "rails_helper"

# Proves the database-level layers of multitenancy independently of the
# application code: RLS policies, WITH CHECK, composite foreign keys and
# append-only privileges.
#
# Statements expected to fail run inside their own savepoint, exactly as the
# use cases do, so the surrounding transaction remains usable.
RSpec.describe "Tenant isolation in PostgreSQL" do
  def in_savepoint(&)
    ActiveRecord::Base.transaction(requires_new: true, &)
  end

  let(:organization_a) { create(:organization) }
  let(:organization_b) { create(:organization) }
  let(:owner_a) { create(:membership, organization: organization_a) }
  let(:owner_b) { create(:membership, organization: organization_b) }

  it "refuses to insert a row for another organization (WITH CHECK)" do
    user = create(:user)

    in_tenant(organization_a) do
      membership = Membership.new(organization_id: organization_b.id, user:, role: "technician")

      expect { in_savepoint { membership.save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  it "cannot update or read rows of another organization even by primary key" do
    target = owner_b

    in_tenant(organization_a) do
      expect(Membership.where(id: target.id).update_all(role: "auditor")).to eq(0)
      expect(Membership.find_by(id: target.id)).to be_nil
    end
    expect(in_tenant(organization_b) { target.reload.role }).to eq("owner")
  end

  it "rejects references across organizations through composite foreign keys" do
    inviter_from_b = owner_b

    in_tenant(organization_a) do
      invitation = Invitation.new(organization: organization_a, email: "x@servora.test", role: "technician",
        token_digest: Invitation.digest("t"), expires_at: 1.day.from_now, invited_by_membership_id: inviter_from_b.id)

      expect { in_savepoint { invitation.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "keeps audit history append-only for the application role" do
    event = as_member(owner_a) { AuditEvent.record!(action: "test.recorded") }

    in_tenant(organization_a) do
      expect { in_savepoint { AuditEvent.where(id: event.id).update_all(action: "rewritten") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect { in_savepoint { AuditEvent.where(id: event.id).delete_all } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end

  it "resolves invitation tokens through a SECURITY DEFINER function that returns only the tenant id" do
    token = Invitation.generate_token
    invitation = create(:invitation, organization: organization_a, token:)

    resolved = Invitations::Accept.find_organization_id(token)
    definition = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
      SELECT prosecdef, proconfig FROM pg_proc WHERE proname = 'servora_resolve_invitation'
    SQL

    expect(resolved).to eq(invitation.organization_id)
    expect(definition["prosecdef"]).to be(true)
    expect(definition["proconfig"]).to include("search_path=public, pg_temp")
    expect(Invitations::Accept.find_organization_id("token-inexistente")).to be_nil
  end

  it "does not allow organizations to be deleted by the application role" do
    in_tenant(organization_a) do
      expect(Organization.where(id: organization_a.id).delete_all).to eq(0)
    end
  end
end
