# frozen_string_literal: true

# Onboarding form: company data plus operational defaults.
class OrganizationRegistration
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :legal_name, :string
  attribute :document, :string
  attribute :segment, :string, default: "hvac"
  attribute :time_zone, :string, default: "America/Sao_Paulo"
  attribute :travel_buffer_minutes, :integer, default: 30

  validates :name, presence: true, length: { maximum: 120 }
  validates :segment, inclusion: { in: Organization::SEGMENTS.keys }
  validates :time_zone, inclusion: { in: Organization::TIME_ZONES.keys }
  validates :travel_buffer_minutes, numericality: { only_integer: true, in: 0..480 }
  validate :document_is_valid

  def self.model_name
    ActiveModel::Name.new(self, nil, "Organization")
  end

  def save(user:)
    return false unless valid?

    @result = Organizations::Register.new(user:, attributes:).call
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.add(error.attribute, error.message) }
    false
  end

  def organization = @result&.organization

  private

  def document_is_valid
    return if document.blank? || Documents::BrazilianDocument.valid?(document)

    errors.add(:document, "não é um CPF ou CNPJ válido")
  end
end
