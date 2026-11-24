# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invitations do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  describe Invitations::Issue do
    it "creates a pending invitation and records the delivery event in the same transaction" do
      invitation = as_member(owner) { described_class.new(inviter: owner, email: "Nova@Servora.test", role: "technician").call }

      expect(invitation).to have_attributes(email: "nova@servora.test", role: "technician", invited_by_membership_id: owner.id)
      expect(outbox_events(organization).map { |e| [e.event_type, e.aggregate_id] }).to eq([["invitation.issued", invitation.id]])
      expect(Invitations::DeliveryJob).not_to have_been_enqueued
    end

    it "refuses duplicates and existing members" do
      as_member(owner) do
        described_class.new(inviter: owner, email: "dup@servora.test", role: "attendant").call

        expect { described_class.new(inviter: owner, email: "dup@servora.test", role: "attendant").call }
          .to raise_error(Invitations::Issue::AlreadyInvited)
        expect { described_class.new(inviter: owner, email: owner.user.email, role: "attendant").call }
          .to raise_error(Invitations::Issue::AlreadyMember)
      end
    end
  end

  describe Invitations::Deliver do
    it "rotates the token so only the e-mailed link works" do
      original_token = "token-original"
      invitation = create(:invitation, organization:, invited_by: owner, token: original_token)

      expect { described_class.new(organization_id: organization.id, invitation_id: invitation.id).call }
        .to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      delivered_token = mail.text_part.body.to_s[%r{/convites/([\w-]+)}, 1]
      expect(Invitations::Accept.find_organization_id(original_token)).to be_nil
      expect(Invitations::Accept.find_organization_id(delivered_token)).to eq(organization.id)
      expect(mail.to).to eq([invitation.email])
    end

    it "does nothing for invitations that are no longer usable" do
      invitation = create(:invitation, organization:, invited_by: owner, revoked_at: Time.current)

      expect(described_class.new(organization_id: organization.id, invitation_id: invitation.id).call).to be(false)
    end
  end

  describe Invitations::Accept do
    let(:token) { Invitation.generate_token }
    let(:invitee) { create(:user, email: "convidada@servora.test") }

    it "creates the membership once and records acceptance" do
      create(:invitation, organization:, invited_by: owner, email: invitee.email, role: "coordinator", token:)

      membership = described_class.new(token:, user: invitee).call

      expect(membership).to have_attributes(role: "coordinator", user_id: invitee.id, organization_id: organization.id)
      expect { described_class.new(token:, user: invitee).call }
        .to raise_error(Invitations::Accept::InvalidInvitation, "Este convite já foi utilizado.")
    end

    it "refuses an invitation addressed to another e-mail" do
      create(:invitation, organization:, invited_by: owner, email: "outra@servora.test", token:)

      expect { described_class.new(token:, user: invitee).call }
        .to raise_error(Invitations::Accept::InvalidInvitation, /outro e-mail/)
    end

    it "refuses expired and revoked invitations" do
      expired = Invitation.generate_token
      revoked = Invitation.generate_token
      create(:invitation, organization:, invited_by: owner, email: invitee.email, token: expired, expires_at: 1.minute.ago)
      create(:invitation, organization:, invited_by: owner, email: "x@servora.test", token: revoked, revoked_at: Time.current)

      expect do
        described_class.new(token: expired, user: invitee).call
      end.to raise_error(described_class::InvalidInvitation, /expirou/)
      expect do
        described_class.new(token: revoked, user: invitee).call
      end.to raise_error(described_class::InvalidInvitation, /revogado/)
      expect do
        described_class.new(token: "nao-existe",
          user: invitee).call
      end.to raise_error(described_class::InvalidInvitation, /não encontrado/)
    end
  end

  describe Invitations::Revoke do
    it "revokes pending invitations only" do
      invitation = create(:invitation, organization:, invited_by: owner)

      as_member(owner) { described_class.new(invitation:).call }

      expect(in_tenant(organization) { invitation.reload.state }).to eq(:revoked)
      expect { as_member(owner) { described_class.new(invitation:).call } }.to raise_error(Invitations::Revoke::NotRevocable)
    end
  end
end
