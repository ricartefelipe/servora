# frozen_string_literal: true

class Skill < TenantRecord
  has_many :membership_skills, dependent: :delete_all
  has_many :service_type_skills, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :organization_id }

  scope :alphabetical, -> { order(:name) }
end
