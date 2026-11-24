# frozen_string_literal: true

# Photo or document attached to a work order. The file lives in Active
# Storage (tenant-scoped blobs) and is only reachable through
# WorkOrders::EvidencesController.
class WorkOrderEvidence < TenantRecord
  KINDS = { "photo" => "Foto", "document" => "Documento" }.freeze

  belongs_to :work_order
  belongs_to :uploaded_by, class_name: "Membership", foreign_key: :uploaded_by_membership_id, inverse_of: false
  has_one_attached :file

  validates :kind, inclusion: { in: KINDS.keys }
  validates :caption, length: { maximum: 200 }

  scope :recent_first, -> { order(created_at: :desc) }

  def photo? = kind == "photo"
  def kind_label = KINDS.fetch(kind)
end
