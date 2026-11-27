# frozen_string_literal: true

class WorkOrder < TenantRecord
  ORIGINS = {
    "phone" => "Telefone", "email" => "E-mail", "whatsapp" => "Aplicativo de mensagens", "portal" => "Portal do cliente",
    "quote" => "Orçamento aprovado", "preventive" => "Manutenção preventiva", "internal" => "Interna"
  }.freeze
  PRIORITIES = { "low" => "Baixa", "normal" => "Normal", "high" => "Alta", "urgent" => "Urgente" }.freeze

  belongs_to :customer
  belongs_to :service_location
  belongs_to :quote_version, optional: true
  belongs_to :service_type, optional: true
  belongs_to :contract, optional: true, inverse_of: :work_orders
  has_one :maintenance_occurrence, dependent: nil, inverse_of: :work_order
  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, optional: true, inverse_of: false
  belongs_to :requested_by_contact, class_name: "CustomerContact", optional: true

  has_many :work_order_equipment, class_name: "WorkOrderEquipment", dependent: nil, inverse_of: :work_order
  has_many :equipment, through: :work_order_equipment
  has_many :assignments, class_name: "WorkOrderAssignment", dependent: nil, inverse_of: :work_order
  has_many :technicians, through: :assignments, source: :membership
  has_many :items, -> { order(:created_at) }, class_name: "WorkOrderItem", dependent: nil, inverse_of: :work_order
  has_many :checklist_items, -> { order(:position) }, class_name: "WorkOrderChecklistItem", dependent: nil,
    inverse_of: :work_order
  has_many :transitions, -> { order(created_at: :desc) }, class_name: "WorkOrderTransition", dependent: nil,
    inverse_of: :work_order
  has_many :visits, -> { order(:scheduled_start) }, dependent: nil, inverse_of: :work_order
  has_many :time_entries, -> { order(:started_at) }, dependent: nil, inverse_of: :work_order
  has_many :stock_reservations, -> { order(:created_at) }, dependent: nil, inverse_of: :work_order
  has_many :material_consumptions, -> { order(:created_at) }, dependent: nil, inverse_of: :work_order
  has_many :receivables, -> { order(:due_on, :number) }, dependent: nil, inverse_of: :work_order
  has_many :expenses, -> { order(:incurred_on, :created_at) }, dependent: nil, inverse_of: :work_order
  has_many :evidences, -> { order(created_at: :desc) }, class_name: "WorkOrderEvidence", dependent: nil,
    inverse_of: :work_order
  has_many :reports, -> { order(version_number: :desc) }, class_name: "WorkOrderReport", dependent: nil, inverse_of: :work_order

  enum :status, WorkOrders::States.states.index_by(&:itself), validate: true
  enum :priority, PRIORITIES.keys.index_by(&:itself), validate: true, prefix: :priority

  validates :title, presence: true, length: { maximum: 160 }
  validates :problem_description, presence: true, length: { maximum: 5000 }
  validates :origin, inclusion: { in: ORIGINS.keys }

  scope :recent_first, -> { order(requested_at: :desc) }
  scope :open_work, -> { where.not(status: WorkOrders::TERMINAL_STATES) }
  # Work orders with at least one running deadline past or at risk (SlaClock).
  scope :deadline_overdue, ->(now = Time.current) { where(id: SlaClock.overdue(now).select(:work_order_id)) }
  scope :deadline_at_risk, ->(now = Time.current) { where(id: SlaClock.at_risk(now).select(:work_order_id)) }

  def status_label = WorkOrders::LABELS.fetch(status)
  def priority_label = PRIORITIES.fetch(priority)
  def origin_label = ORIGINS.fetch(origin)
  def finished? = WorkOrders::TERMINAL_STATES.include?(status)
end
