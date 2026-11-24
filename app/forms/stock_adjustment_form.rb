# frozen_string_literal: true

# Authorized adjustment after a physical count: the quantity is always
# positive and the direction says whether stock enters or leaves.
class StockAdjustmentForm < StockOperationForm
  DIRECTIONS = { "in" => "Entrada (sobra na contagem)", "out" => "Saída (falta, perda ou avaria)" }.freeze

  attribute :direction, :string, default: "out"
  attribute :unit_cost, :string

  validates :direction, inclusion: { in: DIRECTIONS.keys }
  validates :reason, presence: true, length: { maximum: 500 }

  def self.model_name = ActiveModel::Name.new(self, nil, "StockAdjustment")
  def self.fields = super + %i[direction unit_cost]

  private

  def perform(actor)
    magnitude = Pricing::Amount.quantity(quantity)
    raise Servora::RuleViolation, "Informe uma quantidade positiva; a direção define entrada ou saída." unless magnitude.positive?

    Inventory::Adjust.new(warehouse:, item:, quantity: direction == "in" ? magnitude : -magnitude, actor:, reason:,
      unit_cost: (unit_cost if direction == "in"), idempotency_key: operation_key).call
  end
end
