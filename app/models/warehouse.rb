# frozen_string_literal: true

# Physical stock location: the central storeroom, a technician's own stock or
# a service vehicle. Technician and vehicle stock always has a custodian.
class Warehouse < TenantRecord
  KINDS = { "central" => "Depósito central", "technician" => "Estoque do técnico", "vehicle" => "Veículo" }.freeze

  belongs_to :custodian, class_name: "Membership", foreign_key: :custodian_membership_id, optional: true, inverse_of: false
  has_many :balances, class_name: "StockBalance", dependent: :restrict_with_exception, inverse_of: :warehouse

  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :organization_id }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :custodian, presence: { message: "é obrigatório para estoque de técnico ou veículo" }, unless: lambda {
    kind == "central"
  }

  scope :active, -> { where(active: true) }
  scope :alphabetical, -> { order(:name) }
  scope :in_custody_of, ->(membership) { where(custodian_membership_id: membership.id) }

  def kind_label = KINDS.fetch(kind)
end
