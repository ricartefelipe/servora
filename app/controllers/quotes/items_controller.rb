# frozen_string_literal: true

module Quotes
  class ItemsController < TenantController
    ITEM_FIELDS = %i[catalog_item_id description unit unit_price quantity kind discount].freeze

    before_action :load_quote

    def create
      authorize @quote, :edit_draft?
      add_item(params.expect(item: ITEM_FIELDS))
      redirect_to quote_path(@quote, anchor: "itens"), notice: "Item incluído.", status: :see_other
    rescue Pricing::Amount::InvalidValue, ActiveRecord::RecordInvalid
      redirect_to quote_path(@quote, anchor: "itens"), alert: "Revise quantidade, preço, desconto e descrição do item.",
        status: :see_other
    rescue Servora::RuleViolation => e
      redirect_to quote_path(@quote), alert: e.message, status: :see_other
    end

    def destroy
      authorize @quote, :edit_draft?
      item = tenant_relation(QuoteItem).where(quote_version_id: @quote.current_version_id).find(params.expect(:id))
      Quotes::RemoveItem.new(item:).call
      redirect_to quote_path(@quote, anchor: "itens"), notice: "Item removido.", status: :see_other
    rescue Servora::RuleViolation => e
      redirect_to quote_path(@quote), alert: e.message, status: :see_other
    end

    private

    def load_quote
      @quote = policy_scope(tenant_relation(Quote)).includes(current_version: :items).find(params.expect(:quote_id))
    end

    def add_item(attributes)
      catalog_item = attributes[:catalog_item_id].presence &&
                     policy_scope(tenant_relation(CatalogItem)).active.find(attributes[:catalog_item_id])
      Quotes::AddItem.new(
        version: @quote.current_version, catalog_item:, quantity: attributes[:quantity],
        description: attributes[:description], unit: attributes[:unit].presence || "un", unit_price: attributes[:unit_price],
        kind: attributes[:kind].presence || "other", discount: attributes[:discount].presence || 0
      ).call
    end
  end
end
