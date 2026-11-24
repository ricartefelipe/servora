# frozen_string_literal: true

class QuoteItem < TenantRecord
  KINDS = { "service" => "Serviço", "part" => "Peça", "other" => "Outro" }.freeze

  belongs_to :quote_version, inverse_of: :items
  belongs_to :catalog_item, optional: true

  validates :kind, inclusion: { in: KINDS.keys }
  validates :description, presence: true, length: { maximum: 240 }
  validates :unit, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :discount_amount, numericality: { greater_than_or_equal_to: 0 }

  def pricing_line
    Pricing::Line.build(quantity:, unit_price:, discount: discount_amount, unit_cost:)
  end

  def kind_label = KINDS.fetch(kind)
end
