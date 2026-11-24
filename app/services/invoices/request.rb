# frozen_string_literal: true

module Invoices
  # Requests the NFS-e of a receivable. Stored as pending with a stable
  # external reference and an outbox event; the provider call happens after
  # commit. At most one valid invoice per receivable (unique partial index).
  class Request
    def initialize(receivable:, actor:, description: nil)
      @receivable = receivable
      @actor = actor
      @description = description.to_s.squish.presence
    end

    def call
      settings = FiscalSetting.for(@receivable.organization_id)
      raise Servora::RuleViolation, "Configure os dados fiscais antes de emitir notas." unless settings
      raise Servora::RuleViolation, "Contas canceladas não recebem nota fiscal." if @receivable.canceled?

      ActiveRecord::Base.transaction(requires_new: true) { create(settings) }
    rescue ActiveRecord::RecordNotUnique
      raise Servora::RuleViolation, "Esta conta já tem uma nota fiscal válida ou em emissão."
    end

    private

    def create(settings)
      invoice = ServiceInvoice.create!(organization_id: @receivable.organization_id, receivable: @receivable,
        provider: PaymentIntegration.for(@receivable.organization_id).provider,
        external_reference: "srv-nfse-#{SecureRandom.uuid_v7}",
        amount: @receivable.amount - @receivable.discount_amount, description: description(settings),
        requested_by_membership_id: @actor&.id)
      AuditEvent.record!(action: "service_invoice.requested", auditable: invoice,
        organization: Organization.find(@receivable.organization_id), changes: { amount: invoice.amount })
      Outbox::Publisher.publish!(event_type: "service_invoice.requested", aggregate: invoice,
        dedup_key: "service_invoice.requested:#{invoice.id}")
      invoice
    end

    def description(settings)
      @description || [settings.default_description.presence, @receivable.description].compact.join(" — ")
    end
  end
end
