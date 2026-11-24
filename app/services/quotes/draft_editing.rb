# frozen_string_literal: true

module Quotes
  # Shared guard and recalculation for operations on a draft version.
  module DraftEditing
    class NotEditable < Servora::RuleViolation; end

    private

    def ensure_draft!(version)
      return if version.draft? && version.quote.current_version_id == version.id && !version.quote.closed?

      raise NotEditable, "Esta versão já foi enviada e não pode ser alterada. Crie uma nova versão."
    end

    # Totals are derived from the items with the Pricing rules and stored on the
    # version (the database checks total = subtotal − discount). When items are
    # removed, the global discount is capped at the new subtotal.
    def recalculate!(version)
      version.items.reset
      lines = version.items.map(&:pricing_line)
      discount = [version.discount_amount, Pricing::Totals.from(lines).subtotal].min
      totals = Pricing::Totals.from(lines, discount:)
      version.update!(subtotal: totals.subtotal, discount_amount: totals.discount, total: totals.total)
    end
  end
end
