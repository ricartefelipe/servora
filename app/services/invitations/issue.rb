# frozen_string_literal: true

module Invitations
  # Creates a pending invitation. The clear token is only generated when the
  # e-mail is delivered (see Invitations::Deliver), so it never sits in the
  # database or in the job queue.
  class Issue
    class AlreadyMember < Servora::RuleViolation; end
    class AlreadyInvited < Servora::RuleViolation; end

    def initialize(inviter:, email:, role:)
      @inviter = inviter
      @email = email.to_s.strip.downcase
      @role = role.to_s
    end

    def call
      organization = @inviter.organization
      raise AlreadyMember, "Esta pessoa já faz parte da equipe." if member?(organization)
      raise AlreadyInvited, "Já existe um convite pendente para este e-mail." if pending?(organization)

      invitation = organization.invitations.create!(
        email: @email, role: @role, invited_by: @inviter,
        token_digest: Invitation.digest(Invitation.generate_token),
        expires_at: Invitation::VALIDITY.from_now
      )
      AuditEvent.record!(action: "invitation.issued", auditable: invitation, changes: { email: @email, role: @role })
      Invitations::DeliveryJob.perform_later(organization.id, invitation.id)
      invitation
    end

    private

    def member?(organization)
      organization.memberships.joins(:user).exists?(users: { email: @email })
    end

    def pending?(organization)
      organization.invitations.pending.where(email: @email).exists?(["expires_at > ?", Time.current])
    end
  end
end
