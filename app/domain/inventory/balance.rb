# frozen_string_literal: true

module Inventory
  # Immutable stock position of one item in one warehouse and the pure rules
  # that move it. Every operation returns [new_balance, movement_values].
  #
  # * physical (on_hand), reserved, available = on_hand − reserved;
  # * quantities have 3 decimals; costs 4 decimals; money (total cost) 2;
  # * moving average cost: entries and returns recompute the average,
  #   rounded half up to 4 decimals; outflows use the current average and
  #   never change it.
  Balance = Data.define(:on_hand, :reserved, :average_cost) do
    def self.empty = new(on_hand: BigDecimal("0"), reserved: BigDecimal("0"), average_cost: BigDecimal("0"))

    def available = on_hand - reserved

    def receive(quantity, unit_cost)
      quantity = positive!(quantity)
      cost = Pricing::Amount.cost(unit_cost)
      raise Inventory::InvalidQuantity, "unit cost cannot be negative" if cost.negative?

      new_on_hand = on_hand + quantity
      average = Pricing::Amount.cost(((on_hand * average_cost) + (quantity * cost)) / new_on_hand)
      [with(on_hand: new_on_hand, average_cost: average), cost]
    end

    def reserve(quantity)
      quantity = positive!(quantity)
      raise Inventory::InsufficientAvailable.new(available, quantity) if quantity > available

      [with(reserved: reserved + quantity), average_cost]
    end

    def release(quantity)
      quantity = positive!(quantity)
      raise Inventory::InvalidQuantity, "cannot release more than reserved" if quantity > reserved

      [with(reserved: reserved - quantity), average_cost]
    end

    # Consumes physical stock; from_reservation also lowers the reserved amount.
    def consume(quantity, from_reservation: false)
      quantity = positive!(quantity)
      if from_reservation
        raise Inventory::InvalidQuantity, "cannot consume more than reserved" if quantity > reserved

        return [with(on_hand: on_hand - quantity, reserved: reserved - quantity), average_cost]
      end
      raise Inventory::InsufficientAvailable.new(available, quantity) if quantity > available

      [with(on_hand: on_hand - quantity), average_cost]
    end

    def issue(quantity) = consume(quantity)

    def outflow_cost(quantity) = Pricing::Amount.money(Pricing::Amount.quantity(quantity) * average_cost)

    private

    def positive!(quantity)
      value = Pricing::Amount.quantity(quantity)
      raise Inventory::InvalidQuantity, "quantity must be positive" unless value.positive?

      value
    end
  end
end
