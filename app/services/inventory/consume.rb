# frozen_string_literal: true

module Inventory
  # Records material used on a work order, priced at the moving average cost of
  # that moment (stored on the consumption and never recalculated). With an
  # idempotency key, resubmissions (double click, field app retries) do not
  # consume twice.
  class Consume
    def initialize(work_order:, warehouse:, item:, quantity:, actor:, reservation: nil, idempotency_key: nil)
      @work_order = work_order
      @warehouse = warehouse
      @item = item
      @quantity = Pricing::Amount.quantity(quantity)
      @actor = actor
      @reservation = reservation
      @idempotency_key = idempotency_key.presence
    end

    def call
      Errors.ensure_stockable!(@item)
      Idempotency.perform(@idempotency_key, find: -> { MaterialConsumption.find_by(idempotency_key: @idempotency_key) },
        same: ->(consumption) { same_consumption?(consumption) }) do
        ActiveRecord::Base.transaction(requires_new: true) { consume }
      end
    rescue Inventory::Error => e
      raise Errors.translate(e, @item.name)
    end

    private

    def consume
      Errors.lock_open_work_order!(@work_order)
      lock_reservation!
      ledger = Ledger.new(organization_id: @work_order.organization_id, actor: @actor)
      ledger.with_locked_balances([[@warehouse.id, @item.id]]) do |balances|
        balance = balances.values.first
        state, unit_cost = balance.state.consume(@quantity, from_reservation: @reservation.present?)
        total = Pricing::Amount.money(@quantity * unit_cost)
        movement = ledger.record!(balance, kind: "consumption", state:, quantity: @quantity, unit_cost:, total_cost: total,
          work_order_id: @work_order.id, reservation_id: @reservation&.id, idempotency_key: @idempotency_key)
        close_reservation_share
        MaterialConsumption.create!(organization_id: @work_order.organization_id, work_order: @work_order, warehouse: @warehouse,
          catalog_item: @item, reservation: @reservation, movement_id: movement.id, quantity: @quantity, unit_cost:,
          total_cost: total, idempotency_key: @idempotency_key)
      end
    end

    def lock_reservation!
      return unless @reservation

      @reservation.lock!
      matches = @reservation.work_order_id == @work_order.id && @reservation.warehouse_id == @warehouse.id &&
                @reservation.catalog_item_id == @item.id
      raise Errors::InvalidOperation, "A reserva não corresponde ao material informado." unless matches
      raise Errors::InvalidOperation, "Quantidade maior que o saldo reservado." if @quantity > @reservation.remaining
    end

    def close_reservation_share
      return unless @reservation

      consumed = @reservation.consumed_quantity + @quantity
      status = consumed + @reservation.released_quantity >= @reservation.quantity ? "closed" : "active"
      @reservation.update!(consumed_quantity: consumed, status:)
    end

    def same_consumption?(consumption)
      consumption.work_order_id == @work_order.id && consumption.warehouse_id == @warehouse.id &&
        consumption.catalog_item_id == @item.id && consumption.quantity == @quantity
    end
  end
end
