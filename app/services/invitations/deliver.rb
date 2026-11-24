# frozen_string_literal: true

module Invitations
  # Rotates the invitation token and e-mails it. Rotation happens in a short
  # transaction; the SMTP call happens afterwards, outside any transaction.
  # Re-delivering invalidates the previously sent link.
  class Deliver
    def initialize(organization_id:, invitation_id:)
      @organization_id = organization_id
      @invitation_id = invitation_id
    end

    def call
      token, invitation = rotate_token
      return false unless token

      InvitationMailer.invite(invitation:, token:).deliver_now
      true
    end

    private

    def rotate_token
      Servora::Tenancy.with_organization(@organization_id) do
        invitation = Invitation.lock.includes(:organization, invited_by: :user).find_by(id: @invitation_id)
        next [nil, nil] unless invitation&.usable?

        token = Invitation.generate_token
        invitation.update!(token_digest: Invitation.digest(token))
        [token, invitation]
      end
    end
  end
end
