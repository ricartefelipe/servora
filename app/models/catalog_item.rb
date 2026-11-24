# frozen_string_literal: true

# Service or part offered by the organization. Sale price is public to
# operational roles; unit_cost is internal (see CatalogItemPolicy).
class CatalogItem < TenantRecord
  KINDS = { "service" => "Serviço", "part" => "Peça" }.freeze
  UNITS = {
    "un" => "unidade", "h" => "hora", "min" => "minuto", "m" => "metro", "m2" => "m²", "m3" => "m³",
    "kg" => "quilograma", "l" => "litro", "par" => "par", "cj" => "conjunto", "vb" => "verba"
  }.freeze

  enum :kind, KINDS.keys.index_by(&:itself), validate: true

  normalizes :sku, with: ->(value) { value.to_s.strip.upcase.presence }
  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, presence: true, length: { maximum: 160 }
  validates :unit, inclusion: { in: UNITS.keys }
  validates :sku, uniqueness: { scope: :organization_id }, allow_nil: true, length: { maximum: 40 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validates :unit_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :estimated_minutes, numericality: { only_integer: true, in: 1..10_080 }, allow_nil: true
  validate :inventory_only_for_parts

  scope :active, -> { where(active: true) }
  scope :alphabetical, -> { order(:name) }

  def kind_label = KINDS.fetch(kind)
  def unit_label = UNITS.fetch(unit)

  private

  def inventory_only_for_parts
    errors.add(:tracks_inventory, "só se aplica a peças") if tracks_inventory? && !part?
  end
end
