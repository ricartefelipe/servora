# frozen_string_literal: true

module Quotes
  # Adds a line to a draft version. Catalog items are copied (description,
  # unit, price and cost at this moment): later catalog changes do not affect
  # the quote.
  class AddItem
    include DraftEditing

    def initialize(version:, quantity:, catalog_item: nil, description: nil, unit: "un", unit_price: nil, kind: "other",
                   discount: 0)
      @version = version
      @catalog_item = catalog_item
      @attributes = { quantity:, description:, unit:, unit_price:, kind:, discount: }
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @version.lock!
        ensure_draft!(@version)
        item = @version.items.create!(item_attributes)
        recalculate!(@version)
        item
      end
    end

    private

    def item_attributes
      source = @catalog_item ? catalog_attributes : free_attributes
      line = Pricing::Line.build(quantity: @attributes[:quantity], unit_price: source[:unit_price],
        discount: @attributes[:discount], unit_cost: source[:unit_cost])
      source.merge(organization_id: @version.organization_id, quantity: line.quantity, unit_price: line.unit_price,
        discount_amount: line.discount, line_total: line.total, position: @version.items.size + 1)
    end

    def catalog_attributes
      { catalog_item: @catalog_item, kind: @catalog_item.kind, description: @catalog_item.name, unit: @catalog_item.unit,
        unit_price: @attributes[:unit_price].presence || @catalog_item.unit_price, unit_cost: @catalog_item.unit_cost }
    end

    def free_attributes
      { kind: @attributes[:kind], description: @attributes[:description], unit: @attributes[:unit],
        unit_price: @attributes[:unit_price], unit_cost: nil }
    end
  end
end
