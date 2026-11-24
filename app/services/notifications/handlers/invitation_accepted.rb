# frozen_string_literal: true

module Notifications
  module Handlers
    # invitation.accepted → in-app notification to the person who invited.
    class InvitationAccepted
      def call(event, context)
        invitation = Invitation.includes(:accepted_user, :invited_by).find(event.aggregate_id)
        return unless invitation.invited_by.active?

        Notifications::Deliver.new(event:, context:).call(
          recipients: [invitation.invited_by], kind: "invitation.accepted",
          title: "#{invitation.accepted_user.name} entrou na equipe",
          body: "Convite aceito com o perfil #{invitation.role_label}.",
          path: Rails.application.routes.url_helpers.members_path
        )
      end
    end
  end
end
