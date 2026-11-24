# frozen_string_literal: true

module Inventory
  # Moves stock between warehouses (e.g. central → technician van). Both
  # balances are locked in a consistent order and both movements share a
  # transfer group in a single savepoint: there is no half-done transfer.
  # The destination receives at the source's average cost.
  class Transfer
    def initialize(from:, to:, item:, quantity:, actor:, reason: nil, idempotency_key: nil)
      @from = from
      @to = to
      @item = item
      @quantity = Pricing::Amount.quantity(quantity)
      @actor = actor
      @reason = reason.to_s.strip.presence
      @idempotency_key = idempotency_key.presence
    end

    # Returns the outgoing movement; its transfer_group_id links both legs.
    def call
      validate!
      IdempotentOperation.perform(@idempotency_key, find: -> { StockMovement.find_by(idempotency_key: @idempotency_key) },
        same: ->(movement) { same_transfer?(movement) }) { transfer }
    rescue Inventory::Error => e
      raise Errors.translate(e, @item.name)
    end

    private

    def validate!
      Errors.ensure_stockable!(@item)
      raise Errors::InvalidOperation, "Escolha depósitos diferentes." if @from.id == @to.id
      raise Errors::InvalidOperation, "O depósito de destino está inativo." unless @to.active?
    end

    def transfer
      ledger = Ledger.new(organization_id: @from.organization_id, actor: @actor)
      ActiveRecord::Base.transaction(requires_new: true) do
        ledger.with_locked_balances([[@from.id, @item.id], [@to.id, @item.id]]) do |balances|
          move(ledger, balances, SecureRandom.uuid_v7)
        end
      end
    end

    def move(ledger, balances, group)
      source = balances.fetch([@from.id, @item.id])
      target = balances.fetch([@to.id, @item.id])
      source_state, cost = source.state.issue(@quantity)
      total = Pricing::Amount.money(@quantity * cost)
      # Only the outgoing leg carries the idempotency key (the index is unique).
      outgoing = ledger.record!(source, kind: "transfer_out", state: source_state, quantity: @quantity, unit_cost: cost,
        total_cost: total, transfer_group_id: group, reason: @reason, idempotency_key: @idempotency_key)
      target_state, = target.state.receive(@quantity, cost)
      ledger.record!(target, kind: "transfer_in", state: target_state, quantity: @quantity, unit_cost: cost, total_cost: total,
        transfer_group_id: group, reason: @reason)
      outgoing
    end

    def same_transfer?(movement)
      movement.kind == "transfer_out" && movement.warehouse_id == @from.id && movement.catalog_item_id == @item.id &&
        movement.quantity == @quantity
    end
  end
end
