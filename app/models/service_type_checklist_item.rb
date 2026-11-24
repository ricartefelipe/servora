# frozen_string_literal: true

class ServiceTypeChecklistItem < TenantRecord
  KINDS = { "check" => "Confirmação", "text" => "Texto", "number" => "Número" }.freeze

  belongs_to :service_type, inverse_of: :checklist_items

  validates :label, presence: true, length: { maximum: 160 }
  validates :response_kind, inclusion: { in: KINDS.keys }
end
