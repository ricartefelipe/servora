# frozen_string_literal: true

module Inventory
  # Authorized inventory adjustment (count differences, losses). Requires a
  # reason; positive adjustments enter at the informed cost (default: current
  # average), negative ones leave at the current average and can never remove
  # reserved stock.
  class Adjust
    def initialize(warehouse:, item:, quantity:, actor:, reason:, unit_cost: nil, idempotency_key: nil)
      @warehouse = warehouse
      @item = item
      @delta = Pricing::Amount.quantity(quantity)
      @actor = actor
      @reason = reason.to_s.strip
      @unit_cost = unit_cost.presence
      @idempotency_key = idempotency_key.presence
    end

    def call
      validate!
      IdempotentOperation.perform(@idempotency_key, find: -> { StockMovement.find_by(idempotency_key: @idempotency_key) },
        same: ->(movement) { same_adjustment?(movement) }) do
        ledger = Ledger.new(organization_id: @warehouse.organization_id, actor: @actor)
        ActiveRecord::Base.transaction(requires_new: true) do
          ledger.with_locked_balances([[@warehouse.id, @item.id]]) { |balances| adjust(ledger, balances.values.first) }
        end
      end
    rescue Inventory::Error => e
      raise Errors.translate(e, @item.name)
    end

    private

    def validate!
      Errors.ensure_stockable!(@item)
      raise Errors::InvalidOperation, "Informe o motivo do ajuste." if @reason.blank?
      raise Errors::InvalidOperation, "A quantidade do ajuste não pode ser zero." if @delta.zero?
    end

    def adjust(ledger, balance)
      if @delta.positive?
        state, cost = balance.state.receive(@delta, @unit_cost || balance.average_cost)
      else
        state, cost = balance.state.issue(@delta.abs)
      end
      movement = ledger.record!(balance, kind:, state:, quantity: @delta.abs, unit_cost: cost, total_cost: @delta.abs * cost,
        reason: @reason, idempotency_key: @idempotency_key)
      AuditEvent.record!(action: "stock.adjusted", auditable: @item,
        changes: { warehouse: @warehouse.name, delta: @delta, unit_cost: cost, reason: @reason })
      movement
    end

    def kind = @delta.positive? ? "adjustment_in" : "adjustment_out"

    def same_adjustment?(movement)
      movement.kind == kind && movement.warehouse_id == @warehouse.id && movement.catalog_item_id == @item.id &&
        movement.quantity == @delta.abs
    end
  end
end
