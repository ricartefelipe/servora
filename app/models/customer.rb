# frozen_string_literal: true

class Customer < TenantRecord
  KINDS = { "individual" => "Pessoa física", "company" => "Pessoa jurídica" }.freeze

  has_many :service_locations, dependent: :restrict_with_exception
  has_many :contacts, class_name: "CustomerContact", dependent: :restrict_with_exception
  has_many :equipment, dependent: :restrict_with_exception
  has_many :quotes, dependent: :restrict_with_exception

  enum :kind, KINDS.keys.index_by(&:itself), validate: true

  normalizes :document, with: ->(value) { Documents::BrazilianDocument.normalize(value).presence }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :name, :trade_name, with: ->(value) { value.to_s.squish.presence }

  validates :name, presence: true, length: { maximum: 160 }
  validates :trade_name, length: { maximum: 160 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :phone, length: { maximum: 30 }
  validates :document, uniqueness: { scope: :organization_id }, allow_nil: true
  validate :document_matches_kind

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  # Sorted by what lists show (display_name: trade name, else legal name); the
  # legal name and the id break ties so pages never overlap.
  scope :alphabetical, -> { order(Arel.sql("COALESCE(NULLIF(customers.trade_name, ''), customers.name)"), :name, :id) }

  def archived? = archived_at.present?
  def display_name = trade_name.presence || name
  def kind_label = KINDS.fetch(kind)

  private

  def document_matches_kind
    return if document.blank?

    expected = individual? ? :cpf : :cnpj
    actual = Documents::BrazilianDocument.kind(document)
    return if actual == expected

    errors.add(:document, individual? ? "deve ser um CPF válido" : "deve ser um CNPJ válido")
  end
end
