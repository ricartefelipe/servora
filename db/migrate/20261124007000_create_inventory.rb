# frozen_string_literal: true

# Inventory ledger.
#
# * stock_movements is append-only (no UPDATE/DELETE for the application role)
#   and stores the balance values after each movement;
# * stock_balances can only change together with a new movement: a trigger
#   checks that last_movement_id points to a different movement of the same
#   warehouse and item, whose "after" values equal the new balance and whose
#   quantity explains exactly the change (by movement kind);
# * constraints keep on hand >= 0, reserved >= 0 and reserved <= on hand.
class CreateInventory < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  MOVEMENT_KINDS = %w[entry reservation reservation_release consumption return transfer_out transfer_in adjustment_in
                      adjustment_out].freeze

  def up
    create_tenant_table :warehouses do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "central"
      t.boolean :active, null: false, default: true
    end
    add_tenant_reference :warehouses, :memberships, column: :custodian_membership_id
    add_index :warehouses, %i[organization_id name], unique: true
    add_inclusion_constraint :warehouses, :kind, %w[central technician vehicle], name: "warehouses_kind"
    add_check_constraint :warehouses, "kind = 'central' OR custodian_membership_id IS NOT NULL", name: "warehouses_custodian"

    create_tenant_table :stock_movements, timestamps: :created_only do |t|
      t.string :kind, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :unit_cost, precision: 14, scale: 4, null: false
      t.decimal :total_cost, precision: 14, scale: 2, null: false
      t.decimal :on_hand_after, precision: 14, scale: 3, null: false
      t.decimal :reserved_after, precision: 14, scale: 3, null: false
      t.decimal :average_cost_after, precision: 14, scale: 4, null: false
      t.uuid :transfer_group_id
      t.uuid :reservation_id
      t.string :idempotency_key
      t.text :reason
      t.uuid :actor_membership_id
      t.datetime :occurred_at, null: false
    end
    add_tenant_reference :stock_movements, :warehouses, column: :warehouse_id, null: false, index: false
    add_tenant_reference :stock_movements, :catalog_items, column: :catalog_item_id, null: false, index: false
    add_tenant_reference :stock_movements, :work_orders, column: :work_order_id
    add_index :stock_movements, %i[organization_id warehouse_id catalog_item_id occurred_at],
      name: "index_stock_movements_history"
    add_index :stock_movements, %i[organization_id idempotency_key], unique: true, where: "idempotency_key IS NOT NULL",
      name: "index_stock_movements_idempotency"
    add_inclusion_constraint :stock_movements, :kind, MOVEMENT_KINDS, name: "stock_movements_kind"
    add_check_constraint :stock_movements,
      "quantity > 0 AND unit_cost >= 0 AND total_cost >= 0 AND on_hand_after >= 0 AND reserved_after >= 0 " \
      "AND reserved_after <= on_hand_after AND average_cost_after >= 0",
      name: "stock_movements_values"

    create_tenant_table :stock_balances do |t|
      t.decimal :on_hand, precision: 14, scale: 3, null: false, default: 0
      t.decimal :reserved, precision: 14, scale: 3, null: false, default: 0
      t.decimal :average_cost, precision: 14, scale: 4, null: false, default: 0
      t.decimal :minimum_quantity, precision: 14, scale: 3, null: false, default: 0
      t.uuid :last_movement_id
    end
    add_tenant_reference :stock_balances, :warehouses, column: :warehouse_id, null: false, index: false
    add_tenant_reference :stock_balances, :catalog_items, column: :catalog_item_id, null: false
    add_tenant_foreign_key :stock_balances, :stock_movements, column: :last_movement_id
    add_index :stock_balances, %i[organization_id warehouse_id catalog_item_id], unique: true, name: "index_stock_balances_unique"
    add_check_constraint :stock_balances,
      "on_hand >= 0 AND reserved >= 0 AND reserved <= on_hand AND average_cost >= 0 AND minimum_quantity >= 0",
      name: "stock_balances_values"

    create_tenant_table :stock_reservations do |t|
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :consumed_quantity, precision: 14, scale: 3, null: false, default: 0
      t.decimal :released_quantity, precision: 14, scale: 3, null: false, default: 0
      t.string :status, null: false, default: "active"
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :stock_reservations, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :stock_reservations, :warehouses, column: :warehouse_id, null: false, index: false
    add_tenant_reference :stock_reservations, :catalog_items, column: :catalog_item_id, null: false, index: false
    add_inclusion_constraint :stock_reservations, :status, %w[active closed], name: "stock_reservations_status"
    add_check_constraint :stock_reservations,
      "quantity > 0 AND consumed_quantity >= 0 AND released_quantity >= 0 AND consumed_quantity + released_quantity <= quantity",
      name: "stock_reservations_quantities"

    # Material actually used on a work order, with the moving average cost at
    # the moment of consumption (never recalculated).
    create_tenant_table :material_consumptions do |t|
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :returned_quantity, precision: 14, scale: 3, null: false, default: 0
      t.decimal :unit_cost, precision: 14, scale: 4, null: false
      t.decimal :total_cost, precision: 14, scale: 2, null: false
      t.string :idempotency_key
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :material_consumptions, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :material_consumptions, :warehouses, column: :warehouse_id, null: false, index: false
    add_tenant_reference :material_consumptions, :catalog_items, column: :catalog_item_id, null: false, index: false
    add_tenant_reference :material_consumptions, :stock_reservations, column: :reservation_id, index: false
    add_tenant_reference :material_consumptions, :stock_movements, column: :movement_id, null: false, index: false
    add_index :material_consumptions, %i[organization_id idempotency_key], unique: true, where: "idempotency_key IS NOT NULL",
      name: "index_material_consumptions_idempotency"
    add_check_constraint :material_consumptions, "quantity > 0 AND returned_quantity >= 0 AND returned_quantity <= quantity",
      name: "material_consumptions_returns"

    execute <<~SQL
      CREATE FUNCTION servora_guard_stock_balance() RETURNS trigger
        LANGUAGE plpgsql AS $$
        DECLARE
          movement stock_movements%ROWTYPE;
          previous_on_hand numeric := 0;
          previous_reserved numeric := 0;
          on_hand_delta numeric := 0;
          reserved_delta numeric := 0;
        BEGIN
          IF TG_OP = 'INSERT' AND NEW.last_movement_id IS NULL THEN
            IF NEW.on_hand <> 0 OR NEW.reserved <> 0 THEN
              RAISE EXCEPTION 'stock balances start empty; quantities change only through movements'
                USING ERRCODE = 'integrity_constraint_violation';
            END IF;
            RETURN NEW;
          END IF;

          IF TG_OP = 'UPDATE' AND NEW.on_hand = OLD.on_hand AND NEW.reserved = OLD.reserved
             AND NEW.average_cost = OLD.average_cost AND NEW.last_movement_id IS NOT DISTINCT FROM OLD.last_movement_id THEN
            RETURN NEW;
          END IF;

          IF NEW.last_movement_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.last_movement_id IS NOT DISTINCT FROM OLD.last_movement_id) THEN
            RAISE EXCEPTION 'stock balance change requires a new movement'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;

          SELECT * INTO movement FROM stock_movements WHERE id = NEW.last_movement_id;
          IF NOT FOUND
             OR movement.warehouse_id <> NEW.warehouse_id
             OR movement.catalog_item_id <> NEW.catalog_item_id
             OR movement.on_hand_after <> NEW.on_hand
             OR movement.reserved_after <> NEW.reserved
             OR movement.average_cost_after <> NEW.average_cost THEN
            RAISE EXCEPTION 'stock balance does not match its movement'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;

          IF TG_OP = 'UPDATE' THEN
            previous_on_hand := OLD.on_hand;
            previous_reserved := OLD.reserved;
          END IF;

          CASE movement.kind
            WHEN 'entry', 'return', 'transfer_in', 'adjustment_in' THEN
              on_hand_delta := movement.quantity;
            WHEN 'transfer_out', 'adjustment_out' THEN
              on_hand_delta := -movement.quantity;
            WHEN 'reservation' THEN
              reserved_delta := movement.quantity;
            WHEN 'reservation_release' THEN
              reserved_delta := -movement.quantity;
            WHEN 'consumption' THEN
              on_hand_delta := -movement.quantity;
              IF movement.reservation_id IS NOT NULL THEN
                reserved_delta := -movement.quantity;
              END IF;
          END CASE;

          IF NEW.on_hand <> previous_on_hand + on_hand_delta OR NEW.reserved <> previous_reserved + reserved_delta THEN
            RAISE EXCEPTION 'stock balance change does not match the movement quantity'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;
          RETURN NEW;
        END
      $$;

      CREATE TRIGGER stock_balances_guard
        BEFORE INSERT OR UPDATE ON stock_balances
        FOR EACH ROW EXECUTE FUNCTION servora_guard_stock_balance();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS stock_balances_guard ON stock_balances;
      DROP FUNCTION IF EXISTS servora_guard_stock_balance();
    SQL
    drop_table :material_consumptions
    drop_table :stock_reservations
    drop_table :stock_balances
    drop_table :stock_movements
    drop_table :warehouses
  end
end
