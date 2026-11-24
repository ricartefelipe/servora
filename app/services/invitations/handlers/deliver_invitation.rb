# frozen_string_literal: true

module Invitations
  module Handlers
    # invitation.issued → e-mail delivery job (token rotated at delivery time).
    class DeliverInvitation
      def call(event, context)
        context.enqueue(Invitations::DeliveryJob, event.organization_id, event.aggregate_id)
      end
    end
  end
end
