# frozen_string_literal: true

class ServiceLocation < TenantRecord
  belongs_to :customer
  has_many :equipment, dependent: :restrict_with_exception

  normalizes :state, with: ->(value) { value.to_s.strip.upcase }
  normalizes :postal_code, with: ->(value) { Addresses::BrazilianStates.normalize_postal_code(value) }

  validates :name, :street, :city, presence: true, length: { maximum: 160 }
  validates :state, inclusion: { in: Addresses::BrazilianStates::STATES.keys }
  validates :postal_code, format: { with: /\A\d{8}\z/ }, allow_nil: true
  validates :number, :complement, :district, length: { maximum: 80 }

  scope :active, -> { where(archived_at: nil) }
  scope :alphabetical, -> { order(:name) }

  def archived? = archived_at.present?

  def address_line
    [[street, number].compact_blank.join(", "), complement, district].compact_blank.join(" · ")
  end

  def city_line
    ["#{city}/#{state}", Addresses::BrazilianStates.format_postal_code(postal_code).presence].compact_blank.join(" · ")
  end
end
