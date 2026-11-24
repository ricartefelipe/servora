# frozen_string_literal: true

# Current position of an item in a warehouse. Quantities only change through
# Inventory::Ledger together with a stock movement (enforced by trigger).
class StockBalance < TenantRecord
  belongs_to :warehouse, inverse_of: :balances
  belongs_to :catalog_item
  belongs_to :last_movement, class_name: "StockMovement", optional: true

  BELOW_MINIMUM_SQL = "stock_balances.minimum_quantity > 0 AND " \
                      "stock_balances.on_hand - stock_balances.reserved < stock_balances.minimum_quantity"

  scope :below_minimum, -> { where(BELOW_MINIMUM_SQL) }

  def available = on_hand - reserved
  def state = Inventory::Balance.new(on_hand:, reserved:, average_cost:)
  def stock_value = Pricing::Amount.money(on_hand * average_cost)
  def below_minimum? = minimum_quantity.positive? && available < minimum_quantity
end
