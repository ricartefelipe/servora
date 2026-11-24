# frozen_string_literal: true

module WorkOrders
  # Adds a service or material to a work order. Additional items found during
  # execution start "pending" and are not billable until authorized.
  class AddItem
    class NotAllowed < Servora::RuleViolation; end

    def initialize(work_order:, actor:, quantity:, catalog_item: nil, description: nil, unit: "un", unit_price: nil,
                   kind: "service")
      @work_order = work_order
      @actor = actor
      @catalog_item = catalog_item
      @attributes = { quantity:, description:, unit:, unit_price:, kind: }
    end

    def call
      raise NotAllowed, "Ordens concluídas ou canceladas não recebem novos itens." if @work_order.finished?

      source = item_source
      line = Pricing::Line.build(quantity: @attributes[:quantity], unit_price: source[:unit_price], unit_cost: source[:unit_cost])
      item = @work_order.items.create!(source.merge(
        organization_id: @work_order.organization_id, source: "additional", authorization_status: "pending",
        quantity: line.quantity, unit_price: line.unit_price, discount_amount: 0, line_total: line.total
      ))
      AuditEvent.record!(action: "work_order.item_added", auditable: @work_order, changes: { description: item.description })
      item
    end

    private

    def item_source
      if @catalog_item
        { catalog_item: @catalog_item, kind: @catalog_item.kind, description: @catalog_item.name, unit: @catalog_item.unit,
          unit_price: @attributes[:unit_price].presence || @catalog_item.unit_price, unit_cost: @catalog_item.unit_cost }
      else
        { kind: @attributes[:kind], description: @attributes[:description], unit: @attributes[:unit],
          unit_price: @attributes[:unit_price], unit_cost: nil }
      end
    end
  end
end
