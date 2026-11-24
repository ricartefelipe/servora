# frozen_string_literal: true

class Holiday < TenantRecord
  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :date, presence: true, uniqueness: { scope: :organization_id }
  validates :name, presence: true, length: { maximum: 80 }

  scope :upcoming_first, -> { order(:date) }
end
