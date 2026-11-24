# frozen_string_literal: true

module InventoryHelpers
  def stock_part(organization, **attributes)
    create(:catalog_item, :part, organization:, **attributes)
  end

  def receive_stock(warehouse, item, quantity, unit_cost, actor: nil, key: nil)
    in_tenant(warehouse.organization_id) do
      Inventory::Receive.new(warehouse:, item:, quantity:, unit_cost:, actor:, idempotency_key: key).call
    end
  end

  def balance_of(warehouse, item)
    in_tenant(warehouse.organization_id) do
      StockBalance.find_by!(warehouse_id: warehouse.id, catalog_item_id: item.id)
    end
  end

  # [on_hand, reserved, average_cost] as strings, for compact expectations.
  def position(warehouse, item)
    balance = balance_of(warehouse, item)
    [balance.on_hand, balance.reserved, balance.average_cost].map { |value| value.to_s("F") }
  end
end

RSpec.configure do |config|
  config.include InventoryHelpers
end
