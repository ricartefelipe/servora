# frozen_string_literal: true

module Invoices
  # Cancels an invoice. Invoices never sent (or rejected) are canceled locally;
  # issued ones are canceled at the provider after commit.
  class Cancel
    def initialize(invoice:, reason:, actor:)
      @invoice = invoice
      @reason = reason.to_s.strip
      @actor = actor
    end

    def call
      raise Servora::RuleViolation, "Informe o motivo do cancelamento." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        @invoice.lock!
        at_provider = @invoice.external_id.present? && %w[authorized scheduled].include?(@invoice.status)
        cancelable = at_provider || %w[pending error].include?(@invoice.status)
        raise Servora::RuleViolation, "Esta nota não pode ser cancelada agora." unless cancelable

        @invoice.update!(status: at_provider ? "canceling" : "canceled")
        AuditEvent.record!(action: "service_invoice.cancel_requested", auditable: @invoice, changes: { reason: @reason })
        if at_provider
          Outbox::Publisher.publish!(event_type: "service_invoice.cancel_requested", aggregate: @invoice,
            dedup_key: "service_invoice.cancel_requested:#{@invoice.id}")
        end
        @invoice
      end
    end
  end
end
