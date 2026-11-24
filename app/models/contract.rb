# frozen_string_literal: true

# Maintenance contract with a customer. Commercial terms are versioned
# (contract_versions, append-only); status changes go through Contracts::*.
class Contract < TenantRecord
  STATUSES = { "draft" => "Rascunho", "active" => "Vigente", "suspended" => "Suspenso", "ended" => "Encerrado" }.freeze
  TERM_FIELDS = %w[title starts_on ends_on monthly_fee monthly_visit_limit covers_parts scope].freeze

  belongs_to :customer
  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, optional: true, inverse_of: false
  has_many :versions, -> { order(version_number: :desc) }, class_name: "ContractVersion", dependent: nil, inverse_of: :contract
  has_many :contract_service_types, dependent: nil, inverse_of: :contract
  has_many :service_types, through: :contract_service_types
  has_many :maintenance_plans, -> { order(:title) }, dependent: nil, inverse_of: :contract
  has_many :work_orders, dependent: nil, inverse_of: :contract

  normalizes :title, with: ->(value) { value.to_s.squish }

  validates :title, presence: true, length: { maximum: 160 }
  validates :starts_on, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }
  validates :monthly_visit_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :ends_after_start

  scope :recent_first, -> { order(created_at: :desc) }
  scope :in_force_on, lambda { |date|
    where(status: "active").where(starts_on: ..date).where("contracts.ends_on IS NULL OR contracts.ends_on >= ?", date)
  }

  def status_label = STATUSES.fetch(status)
  def active? = status == "active"
  def ended? = status == "ended"
  def in_force_on?(date) = active? && starts_on <= date && (ends_on.nil? || ends_on >= date)
  def terms = attributes.slice(*TERM_FIELDS).merge("service_type_ids" => contract_service_types.map(&:service_type_id).sort)

  private

  def ends_after_start
    return if ends_on.blank? || starts_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "deve ser igual ou posterior ao início")
  end
end
