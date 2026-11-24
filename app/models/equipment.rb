# frozen_string_literal: true

# Installed asset at a customer's service location. The database guarantees
# the location belongs to the same customer (composite foreign key) and keeps
# relocation/ownership history in equipment_events.
class Equipment < TenantRecord
  STATUSES = {
    "operational" => "Operando",
    "attention" => "Requer atenção",
    "inoperative" => "Parado",
    "decommissioned" => "Desativado"
  }.freeze

  belongs_to :customer
  belongs_to :service_location
  # History rows are append-only for the application role; the database
  # cascades them only when an unused, never-serviced record is removed.
  has_many :events, -> { order(occurred_at: :desc) }, class_name: "EquipmentEvent", dependent: nil,
    inverse_of: :equipment

  enum :operational_status, STATUSES.keys.index_by(&:itself), validate: true, prefix: :status

  normalizes :serial_number, :asset_tag, with: ->(value) { value.to_s.strip.upcase.presence }
  normalizes :manufacturer, :model, :equipment_type, with: ->(value) { value.to_s.squish.presence }

  validates :equipment_type, presence: true, length: { maximum: 80 }
  validates :manufacturer, :model, :capacity, length: { maximum: 80 }
  validates :serial_number, uniqueness: { scope: %i[organization_id manufacturer] }, allow_nil: true
  validates :asset_tag, uniqueness: { scope: :organization_id }, allow_nil: true
  validate :location_belongs_to_customer
  validate :warranty_after_installation

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived? = archived_at.present?
  def status_label = STATUSES.fetch(operational_status)

  def title
    [equipment_type, manufacturer, model].compact_blank.join(" · ")
  end

  def under_warranty?(on: Date.current)
    warranty_until.present? && warranty_until >= on
  end

  private

  def location_belongs_to_customer
    return if service_location.nil? || service_location.customer_id == customer_id

    errors.add(:service_location, "deve pertencer ao cliente proprietário")
  end

  def warranty_after_installation
    return if warranty_until.blank? || installed_on.blank? || warranty_until >= installed_on

    errors.add(:warranty_until, "não pode ser anterior à instalação")
  end
end
