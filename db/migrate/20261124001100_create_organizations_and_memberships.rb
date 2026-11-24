# frozen_string_literal: true

class CreateOrganizationsAndMemberships < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  ROLES = %w[owner admin coordinator attendant technician finance auditor].freeze

  def up
    create_table :organizations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      t.string :legal_name
      t.string :document
      t.string :segment, null: false, default: "other"
      t.string :time_zone, null: false, default: "America/Sao_Paulo"
      t.string :status, null: false, default: "active"
      t.integer :travel_buffer_minutes, null: false, default: 30
      t.boolean :mfa_required_for_privileged, null: false, default: true
      t.datetime :onboarding_completed_at
      t.timestamps
    end

    add_check_constraint :organizations, "status IN ('active', 'suspended')", name: "organizations_status"
    add_check_constraint :organizations, "travel_buffer_minutes BETWEEN 0 AND 480", name: "organizations_travel_buffer"
    add_check_constraint :organizations, "document IS NULL OR document ~ '^([0-9]{11}|[0-9A-Z]{12}[0-9]{2})$'",
      name: "organizations_document_digits"

    create_tenant_table :memberships, isolation: false do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false
      t.string :status, null: false, default: "active"
      t.string :job_title
      t.string :phone
      # Internal labor cost per hour (BRL, 4 decimals). Visible only with :costs_view.
      t.decimal :hourly_cost, precision: 14, scale: 4
      t.datetime :deactivated_at
      t.uuid :deactivated_by_user_id
    end

    add_index :memberships, %i[organization_id user_id], unique: true
    add_check_constraint :memberships, "role IN (#{ROLES.map { |r| quote(r) }.join(", ")})", name: "memberships_role"
    add_check_constraint :memberships, "status IN ('active', 'deactivated')", name: "memberships_status"
    add_check_constraint :memberships, "hourly_cost IS NULL OR hourly_cost >= 0", name: "memberships_hourly_cost"

    # Organizations: a row is visible inside its own context or to a user who
    # holds an active membership in it (organization picker). Writes only
    # happen inside the organization's own context. There is no DELETE policy.
    # Memberships: visible inside the organization context or to their own user.
    execute <<~SQL
      ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
      CREATE POLICY organizations_select ON organizations FOR SELECT
        USING (
          id = servora_current_organization_id()
          OR EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.organization_id = organizations.id
              AND m.user_id = servora_current_user_id()
              AND m.status = 'active'
          )
        );
      CREATE POLICY organizations_insert ON organizations FOR INSERT
        WITH CHECK (id = servora_current_organization_id());
      CREATE POLICY organizations_update ON organizations FOR UPDATE
        USING (id = servora_current_organization_id())
        WITH CHECK (id = servora_current_organization_id());

      ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
      CREATE POLICY memberships_select ON memberships FOR SELECT
        USING (organization_id = servora_current_organization_id() OR user_id = servora_current_user_id());
      CREATE POLICY memberships_insert ON memberships FOR INSERT
        WITH CHECK (organization_id = servora_current_organization_id());
      CREATE POLICY memberships_update ON memberships FOR UPDATE
        USING (organization_id = servora_current_organization_id())
        WITH CHECK (organization_id = servora_current_organization_id());
    SQL
  end

  def down
    execute "DROP POLICY IF EXISTS organizations_select ON organizations"
    drop_table :memberships
    drop_table :organizations
  end
end
