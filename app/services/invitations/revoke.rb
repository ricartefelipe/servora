# frozen_string_literal: true

module Invitations
  class Revoke
    class NotRevocable < Servora::RuleViolation; end

    def initialize(invitation:)
      @invitation = invitation
    end

    def call
      @invitation.with_lock do
        raise NotRevocable, "Somente convites pendentes podem ser revogados." unless @invitation.usable?

        @invitation.update!(revoked_at: Time.current)
      end
      AuditEvent.record!(action: "invitation.revoked", auditable: @invitation, changes: { email: @invitation.email })
      @invitation
    end
  end
end
