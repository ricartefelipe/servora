# frozen_string_literal: true

# Amount to be received for a work order (one or more installments). Values
# change only through the Receivables::* use cases, which lock the row and
# record a financial event for every change.
class Receivable < TenantRecord
  STATUSES = { "open" => "Em aberto", "partially_paid" => "Parcialmente paga", "paid" => "Quitada",
               "canceled" => "Cancelada" }.freeze

  belongs_to :work_order, inverse_of: :receivables
  belongs_to :customer
  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, optional: true, inverse_of: false
  has_many :payments, -> { order(:paid_at) }, dependent: nil, inverse_of: :receivable
  has_many :charges, -> { order(:created_at) }, class_name: "PaymentCharge", dependent: nil, inverse_of: :receivable
  has_many :service_invoices, -> { order(:created_at) }, dependent: nil, inverse_of: :receivable
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "FinancialEvent", dependent: nil, inverse_of: :receivable

  validates :description, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :active, -> { where.not(status: "canceled") }
  scope :outstanding, -> { where(status: %w[open partially_paid]) }
  scope :overdue, ->(today = Time.zone.today) { outstanding.where(due_on: ...today) }
  scope :recent_first, -> { order(due_on: :desc, number: :desc) }

  def position = Receivables::Position.new(amount:, discount: discount_amount, paid: paid_amount, refunded: refunded_amount)
  def status_label = STATUSES.fetch(status)
  def canceled? = status == "canceled"
  def outstanding? = %w[open partially_paid].include?(status)
  def overdue?(today = Time.zone.today) = outstanding? && due_on < today
  delegate :balance, to: :position
  def active_charge = charges.find { |charge| PaymentCharge::ACTIVE_STATUSES.include?(charge.status) }
end
