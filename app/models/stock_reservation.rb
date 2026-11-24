# frozen_string_literal: true

# Quantity set aside for a work order. Remaining = reserved − consumed −
# released; a reservation closes when nothing remains.
class StockReservation < TenantRecord
  belongs_to :work_order, inverse_of: :stock_reservations
  belongs_to :warehouse
  belongs_to :catalog_item

  scope :active, -> { where(status: "active") }

  def remaining = quantity - consumed_quantity - released_quantity
  def active? = status == "active"
end
