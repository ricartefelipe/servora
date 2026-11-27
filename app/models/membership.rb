# frozen_string_literal: true

class Membership < TenantRecord
  ROLE_LABELS = {
    "owner" => "Proprietário",
    "admin" => "Administrador",
    "coordinator" => "Coordenador operacional",
    "attendant" => "Atendente",
    "technician" => "Técnico",
    "finance" => "Financeiro",
    "auditor" => "Auditor"
  }.freeze

  belongs_to :user
  has_many :membership_skills, dependent: nil
  has_many :skills, through: :membership_skills
  has_many :work_schedules, -> { order(:weekday, :start_minute) }, dependent: nil, inverse_of: :membership
  has_many :allocations, class_name: "TechnicianAllocation", dependent: nil

  enum :role, Authorization::Permissions::ROLES.index_by(&:itself), validate: true
  enum :status, { active: "active", deactivated: "deactivated" }, validate: true

  validates :user_id, uniqueness: { scope: :organization_id }
  validates :hourly_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :job_title, :phone, length: { maximum: 80 }

  scope :ordered, -> { joins(:user).order("users.name") }
  scope :technicians, -> { active.where(role: "technician") }

  def can?(permission)
    active? && Authorization::Permissions.granted?(role, permission)
  end

  # Members who execute work orders without managing the schedule (technicians)
  # work from the field area: it is where they land and where "agenda" points.
  def field_only?
    can?(:work_orders_execute) && !can?(:schedule_manage)
  end

  # Members who follow the audit trail without operating anything (auditors):
  # they land on it, like technicians land on the field area.
  def audit_only?
    can?(:audit_view) && Authorization::Permissions.for(role).none? do |permission|
      permission == :work_orders_execute || permission.end_with?("_manage")
    end
  end

  def privileged?
    Authorization::Permissions.privileged?(role)
  end

  def role_label
    ROLE_LABELS.fetch(role)
  end

  def working_hours = Scheduling::WorkingHours.new(work_schedules.map(&:slot))
end
