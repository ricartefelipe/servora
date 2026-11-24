# frozen_string_literal: true

class Organization < ApplicationRecord
  SEGMENTS = {
    "hvac" => "Climatização e refrigeração",
    "building" => "Manutenção predial",
    "technical_assistance" => "Assistência técnica",
    "commercial_equipment" => "Equipamentos comerciais",
    "other" => "Outro segmento"
  }.freeze

  # Brazilian IANA time zones offered to organizations.
  TIME_ZONES = {
    "America/Noronha" => "Fernando de Noronha (UTC−2)",
    "America/Sao_Paulo" => "Brasília (UTC−3)",
    "America/Cuiaba" => "Cuiabá (UTC−4)",
    "America/Manaus" => "Manaus (UTC−4)",
    "America/Rio_Branco" => "Rio Branco (UTC−5)"
  }.freeze

  has_many :memberships, dependent: :restrict_with_exception
  has_many :invitations, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception
  has_many :outbox_events, dependent: :restrict_with_exception
  has_many :notifications, dependent: :restrict_with_exception
  has_many :customers, dependent: :restrict_with_exception
  has_many :service_locations, dependent: :restrict_with_exception
  has_many :customer_contacts, dependent: :restrict_with_exception
  has_many :equipment, dependent: :restrict_with_exception
  has_many :equipment_events, dependent: :restrict_with_exception
  has_many :catalog_items, dependent: :restrict_with_exception
  has_many :quotes, dependent: :restrict_with_exception
  has_many :quote_versions, dependent: :restrict_with_exception
  has_many :portal_access_grants, dependent: :restrict_with_exception
  has_many :service_types, dependent: :restrict_with_exception
  has_many :work_orders, dependent: :restrict_with_exception
  has_many :visits, dependent: :restrict_with_exception
  has_many :skills, dependent: :restrict_with_exception
  has_many :teams, dependent: :restrict_with_exception
  has_many :technician_allocations, dependent: :restrict_with_exception
  has_many :warehouses, dependent: :restrict_with_exception
  has_many :receivables, dependent: :restrict_with_exception

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  normalizes :document, with: ->(document) { Documents::BrazilianDocument.normalize(document).presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :legal_name, length: { maximum: 160 }
  validates :segment, inclusion: { in: SEGMENTS.keys }
  validates :time_zone, inclusion: { in: TIME_ZONES.keys }
  validates :travel_buffer_minutes, numericality: { only_integer: true, in: 0..480 }
  validate :document_is_valid

  def zone
    ActiveSupport::TimeZone[time_zone]
  end

  def onboarding_completed?
    onboarding_completed_at.present?
  end

  private

  def document_is_valid
    return if document.blank?

    errors.add(:document, :invalid) unless Documents::BrazilianDocument.valid?(document)
  end
end
