# frozen_string_literal: true

# Scheduling and dispatch.
#
# technician_allocations is the source of truth for a technician's time. Every
# active allocation (visit or absence) blocks a half-open interval
# [start, end + travel buffer) and PostgreSQL rejects overlapping active
# allocations of the same technician with an exclusion constraint, even when
# two coordinators schedule at the same instant.
class CreateScheduling < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_tenant_table :skills do |t|
      t.string :name, null: false
    end
    add_index :skills, %i[organization_id name], unique: true

    create_tenant_table :membership_skills
    add_tenant_reference :membership_skills, :memberships, column: :membership_id, null: false, index: false, on_delete: :cascade
    add_tenant_reference :membership_skills, :skills, column: :skill_id, null: false, on_delete: :cascade
    add_index :membership_skills, %i[organization_id membership_id skill_id], unique: true, name: "index_membership_skills_unique"

    create_tenant_table :service_type_skills
    add_tenant_reference :service_type_skills, :service_types, column: :service_type_id, null: false, index: false,
      on_delete: :cascade
    add_tenant_reference :service_type_skills, :skills, column: :skill_id, null: false, on_delete: :cascade
    add_index :service_type_skills, %i[organization_id service_type_id skill_id], unique: true,
      name: "index_service_type_skills_unique"

    create_tenant_table :teams do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
    end
    add_index :teams, %i[organization_id name], unique: true

    create_tenant_table :team_members
    add_tenant_reference :team_members, :teams, column: :team_id, null: false, index: false, on_delete: :cascade
    add_tenant_reference :team_members, :memberships, column: :membership_id, null: false, on_delete: :cascade
    add_index :team_members, %i[organization_id team_id membership_id], unique: true, name: "index_team_members_unique"

    # Weekly working hours in the organization's time zone (minutes from midnight).
    create_tenant_table :work_schedules do |t|
      t.integer :weekday, null: false
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
    end
    add_tenant_reference :work_schedules, :memberships, column: :membership_id, null: false, on_delete: :cascade
    add_check_constraint :work_schedules, "weekday BETWEEN 0 AND 6", name: "work_schedules_weekday"
    add_check_constraint :work_schedules, "start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute",
      name: "work_schedules_interval"

    create_tenant_table :visits do |t|
      t.string :status, null: false, default: "scheduled"
      t.datetime :scheduled_start, null: false
      t.datetime :scheduled_end, null: false
      t.integer :travel_minutes, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.boolean :needs_return, null: false, default: false
      t.text :notes
      t.text :outcome_note
      t.text :cancel_reason
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :visits, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :visits, :teams, column: :team_id, index: false
    add_tenant_reference :visits, :memberships, column: :scheduled_by_membership_id, null: false, index: false
    add_index :visits, %i[organization_id status scheduled_start]
    add_inclusion_constraint :visits, :status, %w[scheduled in_progress completed canceled no_show], name: "visits_status"
    add_check_constraint :visits, "scheduled_start < scheduled_end", name: "visits_period"
    add_check_constraint :visits, "travel_minutes BETWEEN 0 AND 480", name: "visits_travel"

    create_tenant_table :visit_transitions, timestamps: :created_only do |t|
      t.string :from_status
      t.string :to_status, null: false
      t.text :reason
      t.string :actor_label
      t.uuid :actor_membership_id
    end
    add_tenant_reference :visit_transitions, :visits, column: :visit_id, null: false

    create_tenant_table :technician_allocations do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "active"
      t.tstzrange :period, null: false
      t.string :reason
      t.datetime :released_at
    end
    add_tenant_reference :technician_allocations, :memberships, column: :membership_id, null: false, index: false
    add_tenant_reference :technician_allocations, :visits, column: :visit_id
    add_inclusion_constraint :technician_allocations, :kind, %w[visit absence], name: "technician_allocations_kind"
    add_inclusion_constraint :technician_allocations, :status, %w[active released], name: "technician_allocations_status"
    add_check_constraint :technician_allocations,
      "NOT isempty(period) AND lower_inc(period) AND NOT upper_inc(period) AND NOT lower_inf(period) AND NOT upper_inf(period)",
      name: "technician_allocations_half_open_period"
    add_check_constraint :technician_allocations, "(kind = 'visit') = (visit_id IS NOT NULL)",
      name: "technician_allocations_visit_link"

    execute <<~SQL
      ALTER TABLE technician_allocations
        ADD CONSTRAINT technician_allocations_no_overlap
        EXCLUDE USING gist (organization_id WITH =, membership_id WITH =, period WITH &&)
        WHERE (status = 'active');
    SQL
    add_index :technician_allocations, %i[organization_id membership_id status], name: "index_allocations_lookup"
  end

  def down
    drop_table :technician_allocations
    drop_table :visit_transitions
    drop_table :visits
    drop_table :work_schedules
    drop_table :team_members
    drop_table :teams
    drop_table :service_type_skills
    drop_table :membership_skills
    drop_table :skills
  end
end
