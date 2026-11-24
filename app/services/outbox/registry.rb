# frozen_string_literal: true

module Outbox
  # Event type → handlers. Every handler must be idempotent: an event can be
  # processed more than once (lease expiry, crash before acknowledgement).
  module Registry
    HANDLERS = {
      "invitation.issued" => ["Invitations::Handlers::DeliverInvitation"],
      "invitation.accepted" => ["Notifications::Handlers::InvitationAccepted"],
      "quote.sent" => ["Quotes::Handlers::NotifyApprovers"],
      "quote.approved" => ["Notifications::Handlers::QuoteDecided"],
      "quote.rejected" => ["Notifications::Handlers::QuoteDecided"]
    }.freeze

    class UnknownEvent < Servora::PermanentError; end

    module_function

    def handlers_for(event_type)
      names = HANDLERS.fetch(event_type) { raise UnknownEvent, "Nenhum handler registrado para #{event_type}" }
      names.map(&:constantize)
    end
  end
end
