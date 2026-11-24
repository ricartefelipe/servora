# frozen_string_literal: true

module Notifications
  module Handlers
    # quote.approved / quote.rejected → in-app notification to the author and
    # to members who manage quotes.
    class QuoteDecided
      def call(event, context)
        version = QuoteVersion.includes(:decided_by_contact, quote: :created_by).find(event.aggregate_id)
        quote = version.quote
        approved = event.event_type == "quote.approved"
        Notifications::Deliver.new(event:, context:).call(
          recipients: recipients(quote), kind: event.event_type,
          title: "Orçamento #{quote.number} #{approved ? "aprovado" : "recusado"}",
          body: "#{version.decided_by_contact&.name} #{approved ? "aprovou" : "recusou"} a versão #{version.version_number}.",
          path: Rails.application.routes.url_helpers.quote_path(quote)
        )
      end

      private

      def recipients(quote)
        managers = Membership.active.where(role: %w[owner admin coordinator attendant]).to_a
        (managers + [quote.created_by]).select(&:active?).uniq(&:id)
      end
    end
  end
end
