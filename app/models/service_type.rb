# frozen_string_literal: true

class ServiceType < TenantRecord
  has_many :checklist_items, -> { order(:position) }, class_name: "ServiceTypeChecklistItem", dependent: :delete_all,
    inverse_of: :service_type

  accepts_nested_attributes_for :checklist_items, allow_destroy: true, reject_if: ->(attrs) { attrs["label"].blank? }

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :organization_id }

  scope :active, -> { where(active: true) }
  scope :alphabetical, -> { order(:name) }
end
