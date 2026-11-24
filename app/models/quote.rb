# frozen_string_literal: true

class Quote < TenantRecord
  STATUSES = {
    "draft" => "Rascunho", "sent" => "Aguardando cliente", "approved" => "Aprovado", "rejected" => "Recusado",
    "expired" => "Expirado", "converted" => "Convertido em OS", "canceled" => "Cancelado"
  }.freeze

  belongs_to :customer
  belongs_to :service_location
  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, inverse_of: false
  belongs_to :current_version, class_name: "QuoteVersion", optional: true
  belongs_to :approved_version, class_name: "QuoteVersion", optional: true
  has_many :versions, -> { order(:version_number) }, class_name: "QuoteVersion", dependent: nil, inverse_of: :quote
  has_many :events, -> { order(created_at: :desc) }, class_name: "QuoteEvent", dependent: nil, inverse_of: :quote

  enum :status, STATUSES.keys.index_by(&:itself), validate: true

  validates :title, presence: true, length: { maximum: 160 }
  validates :number, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def status_label = STATUSES.fetch(status)
  def editable? = current_version&.draft? && !converted? && !canceled?
  def closed? = converted? || canceled?
end
