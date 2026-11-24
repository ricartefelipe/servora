# frozen_string_literal: true

# One version of a quote. Content is editable only while "draft"; afterwards
# the database rejects changes to items, totals, terms and snapshot.
class QuoteVersion < TenantRecord
  STATUS_LABELS = {
    "draft" => "Rascunho", "sent" => "Enviada", "approved" => "Aprovada", "rejected" => "Recusada",
    "superseded" => "Substituída", "expired" => "Expirada"
  }.freeze

  belongs_to :quote, inverse_of: :versions
  belongs_to :decided_by_contact, class_name: "CustomerContact", optional: true
  belongs_to :decided_by_membership, class_name: "Membership", optional: true
  has_many :items, -> { order(:position, :created_at) }, class_name: "QuoteItem", dependent: nil, inverse_of: :quote_version

  enum :status, Quotes::VersionStates.states.index_by(&:itself), validate: true

  validates :valid_until, presence: true
  validates :discount_amount, numericality: { greater_than_or_equal_to: 0 }

  def status_label = STATUS_LABELS.fetch(status)
  def label = "Versão #{version_number}"

  def expired_on?(date) = valid_until < date

  def pricing_lines
    items.map(&:pricing_line)
  end

  def totals
    Pricing::Totals.from(pricing_lines, discount: discount_amount)
  end
end
