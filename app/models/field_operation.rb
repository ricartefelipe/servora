# frozen_string_literal: true

# Outcome of an operation sent by the field app, keyed by the id generated on
# the device.
class FieldOperation < TenantRecord
  KINDS = %w[time_entry technical_report checklist].freeze

  belongs_to :work_order
  belongs_to :membership

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: %w[applied conflict rejected] }

  def response = { "operation_id" => operation_id, "status" => status, "result" => result }
end
