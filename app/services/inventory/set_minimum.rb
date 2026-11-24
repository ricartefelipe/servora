# frozen_string_literal: true

module Inventory
  # Defines the replenishment threshold of an item in a warehouse. Only the
  # minimum changes; the balance guard trigger accepts updates that leave
  # quantities and cost untouched.
  class SetMinimum
    def initialize(warehouse:, item:, minimum:, actor:)
      @warehouse = warehouse
      @item = item
      @minimum = Pricing::Amount.quantity(minimum)
      @actor = actor
    end

    def call
      Errors.ensure_stockable!(@item)
      raise Errors::InvalidOperation, "O estoque mínimo não pode ser negativo." if @minimum.negative?

      ledger = Ledger.new(organization_id: @warehouse.organization_id, actor: @actor)
      ActiveRecord::Base.transaction(requires_new: true) do
        ledger.with_locked_balances([[@warehouse.id, @item.id]]) do |balances|
          balance = balances.values.first
          previous = balance.minimum_quantity
          next balance if previous == @minimum

          balance.update!(minimum_quantity: @minimum)
          AuditEvent.record!(action: "stock.minimum_changed", auditable: @item,
            changes: { warehouse: @warehouse.name, from: previous, to: @minimum })
          balance
        end
      end
    end
  end
end
