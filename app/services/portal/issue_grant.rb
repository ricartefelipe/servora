# frozen_string_literal: true

module Portal
  # Creates an access grant for a contact. The clear token is only produced at
  # delivery time (Portal::DeliverGrant), so it never sits in the database or
  # in job arguments. Idempotent per outbox event and contact.
  class IssueGrant
    class NotEligible < Servora::RuleViolation; end

    def initialize(contact:, purpose:, quote: nil, outbox_event_id: nil)
      @contact = contact
      @purpose = purpose
      @quote = quote
      @outbox_event_id = outbox_event_id
    end

    def call
      raise NotEligible, "O contato precisa ter acesso ao portal e e-mail cadastrado." unless eligible?

      existing = @outbox_event_id && PortalAccessGrant.find_by(outbox_event_id: @outbox_event_id, contact_id: @contact.id)
      existing || PortalAccessGrant.create!(
        organization_id: @contact.organization_id, contact: @contact, purpose: @purpose, quote: @quote,
        outbox_event_id: @outbox_event_id, expires_at: PortalAccessGrant::VALIDITY.from_now,
        token_digest: PortalAccessGrant.digest(PortalAccessGrant.generate_token)
      )
    end

    private

    def eligible?
      @contact.portal_enabled? && @contact.email.present? && !@contact.archived? && !@contact.customer.archived?
    end
  end
end
