# frozen_string_literal: true

module Quotes
  module Handlers
    # quote.sent → portal access link for each approver contact with portal
    # access (one grant per event and contact; delivery job per grant).
    class NotifyApprovers
      def call(event, context)
        version = QuoteVersion.includes(quote: { customer: :contacts }).find(event.aggregate_id)
        return unless version.sent? && version.quote.current_version_id == version.id

        approvers(version.quote).each do |contact|
          grant = Portal::IssueGrant.new(contact:, purpose: "quote_review", quote: version.quote, outbox_event_id: event.id).call
          context.enqueue(Portal::GrantDeliveryJob, event.organization_id, grant.id)
        end
        Quotes::History.record!(version.quote, kind: "portal_link_sent", version:) if approvers(version.quote).any?
      end

      private

      def approvers(quote)
        quote.customer.contacts.select { |c| c.can_approve? && c.portal_enabled? && c.email.present? && !c.archived? }
      end
    end
  end
end
