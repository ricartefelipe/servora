# frozen_string_literal: true

# Goods receipt (purchase, initial load).
class StockReceiptForm < StockOperationForm
  attribute :unit_cost, :string

  validates :unit_cost, presence: true

  def self.model_name = ActiveModel::Name.new(self, nil, "StockReceipt")
  def self.fields = super + %i[unit_cost]

  private

  def perform(actor)
    Inventory::Receive.new(warehouse:, item:, quantity:, unit_cost:, actor:, reason:, idempotency_key: operation_key).call
  end
end
