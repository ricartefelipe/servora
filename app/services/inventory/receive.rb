# frozen_string_literal: true

module Inventory
  # Goods receipt: increases physical stock and recomputes the moving average.
  class Receive
    def initialize(warehouse:, item:, quantity:, unit_cost:, actor:, reason: nil, idempotency_key: nil)
      @warehouse = warehouse
      @item = item
      @quantity = Pricing::Amount.quantity(quantity)
      @unit_cost = unit_cost
      @actor = actor
      @reason = reason.to_s.strip.presence
      @idempotency_key = idempotency_key.presence
    end

    def call
      Errors.ensure_stockable!(@item)
      raise Errors::InvalidOperation, "O depósito #{@warehouse.name} está inativo." unless @warehouse.active?

      Idempotency.perform(@idempotency_key, find: -> { StockMovement.find_by(idempotency_key: @idempotency_key) },
        same: ->(movement) { same_receipt?(movement) }) { receive }
    rescue Inventory::Error => e
      raise Errors.translate(e, @item.name)
    end

    private

    def receive
      ledger = Ledger.new(organization_id: @warehouse.organization_id, actor: @actor)
      ActiveRecord::Base.transaction(requires_new: true) do
        ledger.with_locked_balances([[@warehouse.id, @item.id]]) do |balances|
          balance = balances.values.first
          state, cost = balance.state.receive(@quantity, @unit_cost)
          movement = ledger.record!(balance, kind: "entry", state:, quantity: @quantity, unit_cost: cost,
            total_cost: @quantity * cost, reason: @reason, idempotency_key: @idempotency_key)
          AuditEvent.record!(action: "stock.received", auditable: @item,
            changes: { warehouse: @warehouse.name, quantity: movement.quantity, unit_cost: cost })
          movement
        end
      end
    end

    def same_receipt?(movement)
      movement.kind == "entry" && movement.warehouse_id == @warehouse.id && movement.catalog_item_id == @item.id &&
        movement.quantity == @quantity
    end
  end
end
