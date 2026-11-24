# frozen_string_literal: true

# Service level agreements per priority, the organization's business calendar
# and one clock per work order and metric (first response, resolution).
#
# Alerts are deduplicated by the clocks themselves: warned_at and
# breach_notified_at are set with a conditional UPDATE, so concurrent or
# repeated scans notify once; sla_clock_events is append-only.
class CreateSla < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :sla_policies do |t|
      t.string :priority, null: false
      t.integer :first_response_minutes, null: false
      t.integer :resolution_minutes, null: false
      t.boolean :business_hours_only, null: false, default: true
      t.integer :warning_percent, null: false, default: 80
    end
    add_index :sla_policies, %i[organization_id priority], unique: true
    add_inclusion_constraint :sla_policies, :priority, %w[low normal high urgent], name: "sla_policies_priority"
    add_check_constraint :sla_policies,
      "first_response_minutes > 0 AND resolution_minutes > 0 AND first_response_minutes <= resolution_minutes " \
      "AND warning_percent >= 50 AND warning_percent <= 95",
      name: "sla_policies_values"

    create_tenant_table :business_hours do |t|
      t.integer :weekday, null: false
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
    end
    add_index :business_hours, %i[organization_id weekday start_minute], unique: true
    add_check_constraint :business_hours,
      "weekday >= 0 AND weekday <= 6 AND start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute",
      name: "business_hours_values"

    create_tenant_table :holidays do |t|
      t.date :date, null: false
      t.string :name, null: false
    end
    add_index :holidays, %i[organization_id date], unique: true

    create_tenant_table :sla_clocks do |t|
      t.string :metric, null: false
      t.string :status, null: false, default: "running"
      t.integer :target_seconds, null: false
      t.integer :consumed_seconds, null: false, default: 0
      t.integer :warning_percent, null: false
      t.boolean :business_hours_only, null: false
      t.integer :segment, null: false, default: 1
      t.datetime :started_at, null: false
      t.datetime :running_since
      t.datetime :due_at
      t.datetime :warn_at
      t.datetime :stopped_at
      t.datetime :breached_at
      t.datetime :warned_at
      t.datetime :breach_notified_at
    end
    add_tenant_reference :sla_clocks, :work_orders, column: :work_order_id, null: false, index: false
    add_index :sla_clocks, %i[work_order_id metric], unique: true
    add_index :sla_clocks, %i[organization_id status due_at]
    add_inclusion_constraint :sla_clocks, :metric, %w[first_response resolution], name: "sla_clocks_metric"
    add_inclusion_constraint :sla_clocks, :status, %w[running paused met breached canceled], name: "sla_clocks_status"
    add_check_constraint :sla_clocks,
      "target_seconds > 0 AND consumed_seconds >= 0 AND segment >= 1 " \
      "AND ((status)::text <> 'running'::text OR (running_since IS NOT NULL AND due_at IS NOT NULL)) " \
      "AND ((status)::text = 'running'::text OR running_since IS NULL)",
      name: "sla_clocks_consistency"

    create_tenant_table :sla_clock_events, timestamps: :created_only do |t|
      t.string :kind, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :details, null: false, default: {}
    end
    add_tenant_reference :sla_clock_events, :sla_clocks, column: :sla_clock_id, null: false
    add_inclusion_constraint :sla_clock_events, :kind,
      %w[started paused resumed met breached warned canceled reopened], name: "sla_clock_events_kind"
  end
end
