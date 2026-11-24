# frozen_string_literal: true

module Invitations
  # Accepts an invitation for the signed-in user. Single use is guaranteed by
  # the row lock plus the unique (organization_id, user_id) membership index.
  class Accept
    class InvalidInvitation < Servora::RuleViolation; end

    def self.find_organization_id(token)
      return nil if token.blank?

      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT servora_resolve_invitation(?)", Invitation.digest(token)])
      )
    end

    def initialize(token:, user:)
      @token = token
      @user = user
    end

    def call
      organization_id = self.class.find_organization_id(@token)
      raise InvalidInvitation, "Convite não encontrado." unless organization_id

      Servora::Tenancy.with_context(organization_id:, user_id: @user.id) do
        invitation = Invitation.lock.find_by!(token_digest: Invitation.digest(@token))
        ensure_acceptable!(invitation)
        membership = invitation.organization.memberships.create!(user: @user, role: invitation.role)
        invitation.update!(accepted_at: Time.current, accepted_user: @user)
        Current.set(user: @user, membership:, organization: invitation.organization) do
          AuditEvent.record!(action: "invitation.accepted", auditable: invitation, changes: { role: invitation.role })
        end
        Outbox::Publisher.publish!(event_type: "invitation.accepted", aggregate: invitation,
          dedup_key: "invitation.accepted:#{invitation.id}")
        membership
      end
    end

    private

    def ensure_acceptable!(invitation)
      raise InvalidInvitation, message_for(invitation.state) unless invitation.usable?
      raise InvalidInvitation, "Este convite foi enviado para outro e-mail." unless invitation.email == @user.email
      return unless Membership.exists?(organization_id: invitation.organization_id, user_id: @user.id)

      raise InvalidInvitation, "Você já faz parte desta organização."
    end

    def message_for(state)
      {
        accepted: "Este convite já foi utilizado.",
        revoked: "Este convite foi revogado.",
        expired: "Este convite expirou. Peça um novo convite ao administrador."
      }.fetch(state)
    end
  end
end
