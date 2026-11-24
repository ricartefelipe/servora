# frozen_string_literal: true

module Servora
  # Helpers for tenant-owned tables. Migrations include this module explicitly.
  #
  # Every tenant table:
  # * uses UUIDv7 primary keys (time ordered, not enumerable);
  # * carries a NOT NULL organization_id referencing organizations;
  # * exposes a UNIQUE (organization_id, id) key so children can declare
  #   composite foreign keys that make cross-organization references impossible;
  # * has Row-Level Security enabled with a policy bound to the transaction-local
  #   setting servora.organization_id (absent setting => no rows).
  module MigrationHelpers
    def create_tenant_table(table_name, **, &)
      create_table(table_name, id: :uuid, default: -> { "uuidv7()" }, **) do |t|
        t.references :organization, type: :uuid, null: false, foreign_key: true, index: false
        yield t if block_given?
        t.timestamps
      end

      add_index table_name, %i[organization_id id], unique: true, name: "index_#{table_name}_on_tenant_key"
      enable_tenant_isolation(table_name)
    end

    # Adds a reference column plus a composite foreign key on
    # (organization_id, <column>) -> <target>(organization_id, id).
    def add_tenant_reference(table_name, target_table, column: nil, null: true, index: true, on_delete: nil)
      column ||= :"#{target_table.to_s.singularize}_id"
      add_column table_name, column, :uuid, null: null
      add_index table_name, [:organization_id, column] if index
      add_tenant_foreign_key(table_name, target_table, column:, on_delete:)
    end

    def add_tenant_foreign_key(table_name, target_table, column:, on_delete: nil)
      add_foreign_key table_name, target_table,
        column: [:organization_id, column],
        primary_key: %i[organization_id id],
        name: "fk_#{table_name}_#{column}_tenant",
        on_delete:
    end

    def enable_tenant_isolation(table_name)
      reversible do |dir|
        dir.up do
          execute <<~SQL.squish
            ALTER TABLE #{quote_table_name(table_name)} ENABLE ROW LEVEL SECURITY;
            CREATE POLICY tenant_isolation ON #{quote_table_name(table_name)}
              USING (organization_id = servora_current_organization_id())
              WITH CHECK (organization_id = servora_current_organization_id());
          SQL
        end
        dir.down do
          execute "DROP POLICY IF EXISTS tenant_isolation ON #{quote_table_name(table_name)}"
        end
      end
    end
  end
end
