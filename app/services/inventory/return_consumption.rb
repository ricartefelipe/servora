# frozen_string_literal: true

module Inventory
  # Returns unused material to stock at the original consumption cost. The
  # returned total can never exceed what was consumed (model rule, row lock and
  # database check constraint).
  class ReturnConsumption
    def initialize(consumption:, quantity:, actor:, reason: nil)
      @consumption = consumption
      @quantity = Pricing::Amount.quantity(quantity)
      @actor = actor
      @reason = reason
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @consumption.lock!
        if @quantity > @consumption.net_quantity
          raise Errors::InvalidOperation, "A devolução (#{Errors.format(@quantity)}) supera o consumido " \
                                          "(#{Errors.format(@consumption.net_quantity)})."
        end

        record_return
        @consumption.update!(returned_quantity: @consumption.returned_quantity + @quantity)
      end
      @consumption
    rescue Inventory::Error => e
      raise Errors.translate(e, @consumption.catalog_item.name)
    end

    private

    def record_return
      ledger = Ledger.new(organization_id: @consumption.organization_id, actor: @actor)
      ledger.with_locked_balances([[@consumption.warehouse_id, @consumption.catalog_item_id]]) do |balances|
        balance = balances.values.first
        state, cost = balance.state.receive(@quantity, @consumption.unit_cost)
        ledger.record!(balance, kind: "return", state:, quantity: @quantity, unit_cost: cost,
          total_cost: @quantity * cost, work_order_id: @consumption.work_order_id, reason: @reason)
      end
    end
  end
end
