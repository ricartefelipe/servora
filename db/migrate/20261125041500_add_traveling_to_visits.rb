# frozen_string_literal: true

# "Em deslocamento": a visit can be marked as on the way before it starts, and
# the field app sends that change (and the customer no-show) through the
# offline operation queue. Rolling back fails while rows use the new values,
# so no recorded trip or field operation is silently rewritten.
class AddTravelingToVisits < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  VISIT_STATUSES = %w[scheduled in_progress completed canceled no_show].freeze
  NEW_VISIT_STATUSES = %w[scheduled traveling in_progress completed canceled no_show].freeze
  OPERATION_KINDS = %w[time_entry technical_report checklist].freeze
  NEW_OPERATION_KINDS = %w[visit_travel visit_no_show].freeze

  def up
    add_column :visits, :travel_started_at, :datetime
    remove_check_constraint :visits, name: "visits_status"
    add_inclusion_constraint :visits, :status, NEW_VISIT_STATUSES, name: "visits_status"
    remove_check_constraint :field_operations, name: "field_operations_kind"
    add_inclusion_constraint :field_operations, :kind, OPERATION_KINDS + NEW_OPERATION_KINDS, name: "field_operations_kind"
  end

  def down
    remove_check_constraint :field_operations, name: "field_operations_kind"
    add_inclusion_constraint :field_operations, :kind, OPERATION_KINDS, name: "field_operations_kind"
    remove_check_constraint :visits, name: "visits_status"
    add_inclusion_constraint :visits, :status, VISIT_STATUSES, name: "visits_status"
    remove_column :visits, :travel_started_at
  end
end
