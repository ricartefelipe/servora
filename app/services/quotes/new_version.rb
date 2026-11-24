# frozen_string_literal: true

module Quotes
  # Starts a new draft from the current version (items copied as they were in
  # that version, not refreshed from the catalog). Any change after sending or
  # approval goes through a new version and a new customer decision.
  class NewVersion
    class NotAllowed < Servora::RuleViolation; end

    def initialize(quote:)
      @quote = quote
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @quote.lock!
        current = QuoteVersion.includes(:items).find(@quote.current_version_id)
        ensure_allowed!(current)
        version = copy(current)
        @quote.update!(current_version: version, status: "draft", approved_version_id: nil)
        History.record!(@quote, kind: "version_created", version:)
        version
      end
    end

    private

    def ensure_allowed!(current)
      raise NotAllowed, "O orçamento está encerrado." if @quote.closed?
      raise NotAllowed, "A versão atual ainda é um rascunho." if current.draft?
    end

    def copy(current)
      version = @quote.versions.create!(organization_id: @quote.organization_id, status: "draft",
        version_number: current.version_number + 1, valid_until: [current.valid_until, today].max,
        payment_terms: current.payment_terms, notes: current.notes, discount_amount: current.discount_amount,
        subtotal: current.subtotal, total: current.total)
      current.items.each do |item|
        version.items.create!(item.attributes.slice(*%w[organization_id kind description unit quantity unit_price unit_cost
                                                        discount_amount line_total position catalog_item_id]))
      end
      version
    end

    def today = Time.current.in_time_zone(@quote.organization.zone).to_date
  end
end
