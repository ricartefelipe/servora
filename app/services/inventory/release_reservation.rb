# frozen_string_literal: true

module Inventory
  # Releases the unconsumed part of a reservation (cancellation, completion or
  # manual release). Idempotent: an already closed reservation is ignored.
  class ReleaseReservation
    def initialize(reservation:, actor: nil, quantity: nil, reason: nil)
      @reservation = reservation
      @actor = actor
      @quantity = quantity
      @reason = reason
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @reservation.lock!
        return @reservation unless @reservation.status == "active" && @reservation.remaining.positive?

        amount = @quantity ? Pricing::Amount.quantity(@quantity) : @reservation.remaining
        raise Errors::InvalidOperation, "Quantidade maior que o saldo reservado." if amount > @reservation.remaining

        release(amount)
      end
      @reservation
    end

    private

    def release(amount)
      ledger = Ledger.new(organization_id: @reservation.organization_id, actor: @actor)
      ledger.with_locked_balances([[@reservation.warehouse_id, @reservation.catalog_item_id]]) do |balances|
        balance = balances.values.first
        state, cost = balance.state.release(amount)
        ledger.record!(balance, kind: "reservation_release", state:, quantity: amount, unit_cost: cost, total_cost: 0,
          work_order_id: @reservation.work_order_id, reservation_id: @reservation.id, reason: @reason)
      end
      released = @reservation.released_quantity + amount
      status = (@reservation.consumed_quantity + released) >= @reservation.quantity ? "closed" : "active"
      @reservation.update!(released_quantity: released, status:)
    end
  end
end
