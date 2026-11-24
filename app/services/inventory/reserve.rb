# frozen_string_literal: true

module Inventory
  # Reserves material for a work order. The balance row lock serializes
  # concurrent reservations: two orders competing for the last unit get one
  # success and one "insufficient available" error. The work order row is
  # locked first, so a reservation never survives a concurrent cancellation.
  class Reserve
    def initialize(work_order:, warehouse:, item:, quantity:, actor:)
      @work_order = work_order
      @warehouse = warehouse
      @item = item
      @quantity = Pricing::Amount.quantity(quantity)
      @actor = actor
    end

    def call
      Errors.ensure_stockable!(@item)
      ledger = Ledger.new(organization_id: @work_order.organization_id, actor: @actor)
      ActiveRecord::Base.transaction(requires_new: true) do
        Errors.lock_open_work_order!(@work_order)
        ledger.with_locked_balances([[@warehouse.id, @item.id]]) { |balances| reserve(ledger, balances.values.first) }
      end
    rescue Inventory::Error => e
      raise Errors.translate(e, @item.name)
    end

    private

    def reserve(ledger, balance)
      state, cost = balance.state.reserve(@quantity)
      reservation = StockReservation.create!(organization_id: @work_order.organization_id, work_order: @work_order,
        warehouse: @warehouse, catalog_item: @item, quantity: @quantity)
      ledger.record!(balance, kind: "reservation", state:, quantity: @quantity, unit_cost: cost, total_cost: 0,
        work_order_id: @work_order.id, reservation_id: reservation.id)
      reservation
    end
  end
end
