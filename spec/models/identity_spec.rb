# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Identity models" do
  describe User do
    it "normalizes e-mail and requires a name" do
      user = described_class.new(email: "  Ana@Servora.TEST ", name: "")

      expect(user.email).to eq("ana@servora.test")
      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it "derives initials for avatars" do
      expect(described_class.new(name: "Ana Paula Ribeiro").display_initials).to eq("AP")
    end
  end

  describe Organization do
    it "validates CPF/CNPJ and time zone" do
      organization = described_class.new(name: "X", document: "11.222.333/0001-82", time_zone: "Mars/Olympus")

      expect(organization).not_to be_valid
      expect(organization.errors.attribute_names).to include(:document, :time_zone)
    end

    it "stores the normalized alphanumeric CNPJ" do
      expect(described_class.new(document: "12.abc.345/01de-35").document).to eq("12ABC34501DE35")
    end
  end

  describe Membership do
    it "loses every permission once deactivated" do
      membership = build(:membership, :owner, status: "deactivated")

      expect(membership.can?(:customers_view)).to be(false)
    end

    it "labels roles in Portuguese" do
      expect(build(:membership, :coordinator).role_label).to eq("Coordenador operacional")
    end
  end

  describe Invitation do
    let(:invitation) { build(:invitation, expires_at: 1.day.from_now) }

    it "is pending until accepted, revoked or expired" do
      expect(invitation.state).to eq(:pending)
      expect(invitation.state(now: 2.days.from_now)).to eq(:expired)
      invitation.revoked_at = Time.current
      expect(invitation.state).to eq(:revoked)
    end

    it "stores only a digest of the token" do
      expect(described_class.digest("abc")).to eq(OpenSSL::Digest::SHA256.hexdigest("abc"))
    end
  end

  describe AuditEvent do
    it "records actor and correlation metadata with redaction" do
      membership = create(:membership)
      Current.request_id = "req-123"

      event = as_member(membership) do
        described_class.record!(action: "test.done", auditable: membership, changes: { "token" => "abc", "role" => "owner" })
      end

      expect(event).to have_attributes(actor_type: "user", actor_user_id: membership.user_id, actor_membership_id: membership.id)
      expect(event.changeset).to eq("token" => "[FILTRADO]", "role" => "owner")
      expect(event.metadata).to include("request_id" => "req-123")
      expect(event).to be_readonly
    end
  end
end
