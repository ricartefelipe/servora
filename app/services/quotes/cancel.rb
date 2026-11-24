# frozen_string_literal: true

module Quotes
  class Cancel
    class NotCancelable < Servora::RuleViolation; end

    def initialize(quote:, reason:)
      @quote = quote
      @reason = reason.to_s.strip
    end

    def call
      raise NotCancelable, "Informe o motivo do cancelamento." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        @quote.lock!
        raise NotCancelable, "Orçamentos convertidos não podem ser cancelados." if @quote.converted?

        @quote.update!(status: "canceled")
        History.record!(@quote, kind: "canceled", note: @reason)
        AuditEvent.record!(action: "quote.canceled", auditable: @quote, changes: { reason: @reason })
      end
      @quote
    end
  end
end
