# frozen_string_literal: true

class Team < TenantRecord
  has_many :team_members, dependent: :delete_all
  has_many :members, through: :team_members, source: :membership

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :organization_id }

  scope :active, -> { where(active: true) }
  scope :alphabetical, -> { order(:name) }
end
