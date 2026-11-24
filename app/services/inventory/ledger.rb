# frozen_string_literal: true

module Inventory
  # Single entry point for balance changes. Callers run inside a transaction:
  #
  #   Ledger.new(...).with_locked_balances([[warehouse_id, item_id], ...]) do |balances|
  #     ledger.record!(balances[key], kind:, state:, ...)
  #   end
  #
  # Balances are created (zeroed) if missing and then locked with
  # SELECT … ORDER BY warehouse_id, catalog_item_id FOR UPDATE, so concurrent
  # operations touching several balances (transfers) always lock in the same
  # order, avoiding deadlocks. Each movement stores the resulting balance; the
  # database trigger rejects balance changes without a matching new movement.
  class Ledger
    BALANCE_KEY = :index_stock_balances_unique

    def initialize(organization_id:, actor: nil)
      @organization_id = organization_id
      @actor = actor
    end

    def with_locked_balances(pairs)
      keys = pairs.uniq.sort
      ensure_balances(keys)
      balances = StockBalance.where(organization_id: @organization_id)
        .where(keys.map { "(warehouse_id = ? AND catalog_item_id = ?)" }.join(" OR "), *keys.flatten)
        .order(:warehouse_id, :catalog_item_id).lock.to_a
      yield balances.index_by { |balance| [balance.warehouse_id, balance.catalog_item_id] }
    end

    def record!(balance, kind:, state:, quantity:, unit_cost:, total_cost:, **details)
      movement = StockMovement.create!(
        organization_id: @organization_id, warehouse_id: balance.warehouse_id, catalog_item_id: balance.catalog_item_id,
        kind:, quantity: Pricing::Amount.quantity(quantity), unit_cost: Pricing::Amount.cost(unit_cost),
        total_cost: Pricing::Amount.money(total_cost), on_hand_after: state.on_hand, reserved_after: state.reserved,
        average_cost_after: state.average_cost, actor_membership_id: @actor&.id, occurred_at: Time.current, **details
      )
      balance.update!(on_hand: state.on_hand, reserved: state.reserved, average_cost: state.average_cost,
        last_movement_id: movement.id)
      movement
    end

    def self.existing_movement(idempotency_key)
      idempotency_key.present? ? StockMovement.find_by(idempotency_key:) : nil
    end

    private

    def ensure_balances(keys)
      now = Time.current
      rows = keys.map do |warehouse_id, catalog_item_id|
        { organization_id: @organization_id, warehouse_id:, catalog_item_id:, created_at: now, updated_at: now }
      end
      StockBalance.insert_all(rows, unique_by: BALANCE_KEY) # rubocop:disable Rails/SkipsModelValidations -- conflict-tolerant creation of empty balances
    end
  end
end
