# frozen_string_literal: true

# Material used on a work order with the moving average cost at consumption
# time. Later purchases never change this cost (historical margin).
class MaterialConsumption < TenantRecord
  belongs_to :work_order, inverse_of: :material_consumptions
  belongs_to :warehouse
  belongs_to :catalog_item
  belongs_to :reservation, class_name: "StockReservation", optional: true
  belongs_to :movement, class_name: "StockMovement"

  def net_quantity = quantity - returned_quantity
  def net_cost = Pricing::Amount.money(net_quantity * unit_cost)
end
