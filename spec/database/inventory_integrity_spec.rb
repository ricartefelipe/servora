# frozen_string_literal: true

require "rails_helper"

# Database guarantees of the inventory ledger, independent of the services:
# balances only change through a matching new movement, movements are
# append-only for the application role, quantities can never go negative and
# rows stay inside their organization.
RSpec.describe "Inventory integrity in PostgreSQL" do
  def in_savepoint(&)
    ActiveRecord::Base.transaction(requires_new: true, &)
  end

  let(:organization) { create(:organization) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:item) { stock_part(organization) }
  let!(:entry) { receive_stock(warehouse, item, "5", "10") }

  it "rejects a direct change of quantities without a new movement" do
    in_tenant(organization) do
      balance = StockBalance.sole

      expect { in_savepoint { balance.update_columns(on_hand: 50) } }
        .to raise_error(ActiveRecord::StatementInvalid, /requires a new movement/)
      expect { in_savepoint { StockBalance.where(id: balance.id).update_all(reserved: 1) } }
        .to raise_error(ActiveRecord::StatementInvalid, /requires a new movement/)
    end
  end

  it "rejects a movement whose quantity does not explain the change" do
    in_tenant(organization) do
      balance = StockBalance.sole
      forged = StockMovement.create!(organization:, warehouse:, catalog_item: item, kind: "entry", quantity: 1, unit_cost: 10,
        total_cost: 10, on_hand_after: 50, reserved_after: 0, average_cost_after: 10, occurred_at: Time.current)

      expect do
        in_savepoint { balance.update_columns(on_hand: 50, last_movement_id: forged.id) }
      end.to raise_error(ActiveRecord::StatementInvalid, /does not match the movement quantity/)
    end
  end

  it "rejects a movement of another item or warehouse" do
    other_item = stock_part(organization)
    foreign = receive_stock(warehouse, other_item, "5", "10")

    in_tenant(organization) do
      balance = StockBalance.find_by!(catalog_item_id: item.id)

      expect { in_savepoint { balance.update_columns(last_movement_id: foreign.id, on_hand: 10) } }
        .to raise_error(ActiveRecord::StatementInvalid, /does not match its movement/)
    end
  end

  it "does not create balances with stock out of thin air" do
    in_tenant(organization) do
      other = create(:warehouse, organization:)

      expect { in_savepoint { StockBalance.insert({ organization_id: organization.id, warehouse_id: other.id, catalog_item_id: item.id, on_hand: 3 }) } } # rubocop:disable Layout/LineLength
        .to raise_error(ActiveRecord::StatementInvalid, /start empty/)
    end
  end

  it "keeps movements append-only for the application role" do
    in_tenant(organization) do
      expect { in_savepoint { StockMovement.where(id: entry.id).update_all(quantity: 1) } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect { in_savepoint { StockMovement.where(id: entry.id).delete_all } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end

  it "enforces non-negative quantities and reserved within physical stock" do
    in_tenant(organization) do
      movement = StockMovement.new(organization:, warehouse:, catalog_item: item, kind: "reservation", quantity: 9, unit_cost: 10,
        total_cost: 0, on_hand_after: 5, reserved_after: 9, average_cost_after: 10, occurred_at: Time.current)

      expect { in_savepoint { movement.save! } }.to raise_error(ActiveRecord::StatementInvalid, /stock_movements_values/)
    end
  end

  it "hides every inventory table from another organization" do
    other = create(:organization)

    in_tenant(other) do
      expect([Warehouse, StockBalance, StockMovement, StockReservation, MaterialConsumption].map(&:count)).to all(eq(0))
    end
  end
end
